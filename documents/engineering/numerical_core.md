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

Training and evaluation select a substrate device and run the model's literal
layer graph through that device. The validated workload plan and the completed
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

`LayerGraph` is the sole graph representation used by training, checkpointing,
and graph inference. Parameterized nodes apply kind-specific input transforms
and backward transforms before their affine projection; convolution nodes lower
to convolution training primitives on the oneDNN path, attention and gated
nodes retain their distinct transforms, normalization computes normalized
outputs, and pooling operates over its defined windows. The pure reference
algebra and backend checks compare those per-kind semantics rather than treating
every tag as a dense or identity alias. Historical audit and validation details
remain in
[Phase 23](../../DEVELOPMENT_PLAN/phase-23-general-differentiable-layer-engine.md).

Phase `23` adds the executable typed layer-graph surface in
`src/JitML/Numerics/LayerGraph.hs` and the public pure reverse-mode API in
`src/JitML/Numerics/Autodiff.hs`. A `LayerGraph` carries input/output tensor
shapes, ordered layer nodes, per-node training-vs-inference mode, activation,
and optional row-major parameter tensors. The catalog represented by graph
nodes covers Dense, Conv2D, Conv3D, MaxPool, AvgPool, GlobalAvgPool, BatchNorm,
LayerNorm, GroupNorm, Dropout, Residual, BasicBlock, BottleneckBlock,
MultiHeadAttention, GeGLU, and patch-embed.

The pure oracle records a forward tape and replays it backward to produce both
input gradients and per-node parameter gradients. `JitML.Numerics.Mlp` is now
the two-layer special case of that graph: its public `mlpBackward` and
`mlpInputGradient` APIs lower the cached MLP forward pass into a two-node graph
tape, call `Autodiff.runBackward`, and project the result back into the legacy
`MlpGradient` record. `JitML.SL.Architecture` also attaches a literal
`archLayerGraph` to every canonical supervised family so later execution,
checkpointing, and inference work can consume the same topology instead of
inferring architecture from a sequence of MLP helper blocks.

The Sprint `23.1` unit coverage checks four invariants: the MLP graph forward
matches the historical MLP forward exactly; finite-difference gradient checks
cover every graph layer kind; a ResNet-shaped graph produces bit-identical
gradients on repeated same-seed runs; and a ViT-shaped patch/attention/head graph
round-trips through the same forward/backward API.

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

Phase `24` Sprint `24.1` binds the canonical supervised rows to literal graph
topology and feature metadata. `ArchitectureFeature` records the feature claims
that product rows make (`Dense`, `BatchNorm`, `Dropout`, `Conv2D`, pooling,
`GroupNorm`, residual, `BasicBlock`, `BottleneckBlock`, attention, patch
embedding, `LayerNorm`, and `GeGLU`), while
`architectureImplementedFeatures` derives the implemented feature set from
`archLayerGraph`. The `jitml-sl-canonicals` gate rejects feature mismatches and
checks the named topology counts: LeNet has two Conv2D nodes, ResNet-20 and
ResNet-56 have 20 and 56 BasicBlock nodes, WideResNet-28-10 has 12
GroupNorm-backed BasicBlock nodes, the small ViT has patch embedding,
MultiHeadAttention, two LayerNorm nodes, and GeGLU, and ResNet-50 has 16
BottleneckBlock nodes. Under Phase `24`'s remediation, the executed supervised
path for these rows uses a real MLP-Mixer-style block with a token-mixing MLP and
executed LayerNorm, so the ViT and deep rows train real token-mixing and
normalization rather than the dense-GEMM stand-in.

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

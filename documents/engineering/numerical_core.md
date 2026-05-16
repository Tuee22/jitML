# Numerical Core

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-6-numerical-core.md, training_workloads.md
**Generated sections**: numerics.layers, numerics.activations, numerics.spectral, numerics.optimizers, numerics.schedulers, numerics.losses

> **Purpose**: Project-specific numerical-core catalog for jitML — the current
> local Haskell catalog under `src/JitML/Numerics/Catalog.hs`, the Dhall mirror
> list tree under `dhall/numerics/`, and the generated documentation tables
> rendered from those sources.

## Catalog Shape

The current numerical core is a local typed Haskell catalog. It enumerates the
constructor names consumed by command summaries, tests, and the JIT codegen
metadata surface. The implementation source is
`src/JitML/Numerics/Catalog.hs`; it exposes `layerCatalog`,
`activationCatalog`, `spectralCatalog`, `optimizerCatalog`,
`schedulerCatalog`, `lossCatalog`, and `renderNumericalCatalog`.

The current schema mirror is a constructor-name audit, not a full parameterized
model schema. The target runtime keeps the same ownership model but adds richer
parameterized constructors and typed records for layer shapes, optimizer
hyperparameters, scheduler parameters, and loss parameters.

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
records remain target work.

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

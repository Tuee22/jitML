# Numerical Core

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-6-numerical-core.md, training_workloads.md
**Generated sections**: numerics.layers, numerics.activations, numerics.spectral, numerics.optimizers, numerics.schedulers, numerics.losses

> **Purpose**: Project-specific numerical-core catalog for jitML — the layer
> catalog (real and complex), activations (real and complex), spectral /
> frequency-domain operations, optimizers, schedulers, loss functions, and
> the Dhall types that mirror every Haskell ADT.

## Catalog Shape

The numerical core is a typed catalog. Every Haskell ADT has a Dhall mirror;
every Dhall type maps to a Haskell ADT. The catalog is the source of truth
for what experiments can declare; the JIT codegen drivers
([jit_codegen_architecture.md](jit_codegen_architecture.md)) consume the
catalog to produce substrate-specific kernels.

The catalog has no runtime behaviour of its own beyond shape validation and
Dhall round-tripping. The training and inference loops in
[training_workloads.md](training_workloads.md) consume the catalog.

## Layers

<!-- jitml:numerics.layers:start -->
| Constructor | Real / Complex | Notes |
|-------------|----------------|-------|
| `Dense` | Real | Fully-connected; init strategy parameterised |
| `Conv1D` / `Conv2D` / `Conv3D` | Real | Standard convolutions; kernel/stride/dilation parameterised |
| `ConvTranspose1D` / `ConvTranspose2D` | Real | Transposed convolution |
| `BatchNorm` | Real | Batch normalisation; running stats; momentum parameter |
| `LayerNorm` | Real | Layer normalisation |
| `GroupNorm` | Real | Group normalisation; group count parameterised |
| `RMSNorm` | Real | Root-mean-square normalisation |
| `Dropout` | Real | Probability parameterised; deterministic per-step under the same RNG seed |
| `ResidualBlock` | Real | Skip-connection block; sub-graph parameterised |
| `MultiHeadAttention` | Real | head count, head dim, dropout parameterised |
| `MultiQueryAttention` | Real | shared-K/V variant of MHA |
| `Embedding` | Real | Token embedding |
| `PositionalEncoding` | Real | Sinusoidal or learned |
| `Pool` | Real | `Max`, `Avg`, or `LP`; window/stride parameterised |
| `Flatten` / `Reshape` / `Permute` | Real | Shape ops |
| `ComplexDense` | Complex | Complex-valued fully-connected |
| `ComplexConv2D` | Complex | Complex-valued 2D convolution |
| `ComplexLayerNorm` | Complex | |
| `ComplexAttention` | Complex | |
<!-- jitml:numerics.layers:end -->

Owning module: `src/JitML/Numerics/Layer.hs` plus the Dhall mirror at
`dhall/numerics/Layer.dhall`.

## Activations

<!-- jitml:numerics.activations:start -->
| Real-valued | Complex-valued |
|-------------|----------------|
| `ReLU`, `LeakyReLU Double`, `PReLU` | `ModReLU Double` |
| `ELU`, `GELU`, `SiLU` (= `Swish`) | `ZReLU` |
| `Tanh`, `Sigmoid`, `Softplus` | `ComplexGELU` |
| `Softmax (Maybe Axis)`, `LogSoftmax (Maybe Axis)` | `ComplexTanh` |
| `HardSigmoid`, `HardSwish`, `Mish` | `ComplexSoftmax (Maybe Axis)` |
<!-- jitml:numerics.activations:end -->

Owning modules: `src/JitML/Numerics/Activation/Real.hs`,
`src/JitML/Numerics/Activation/Complex.hs`.

## Spectral / Frequency-Domain Operations

<!-- jitml:numerics.spectral:start -->
| Constructor | Notes |
|-------------|-------|
| `FFT (Maybe Axis)` | Forward complex FFT |
| `IFFT (Maybe Axis)` | Inverse complex FFT |
| `RFFT` | Real-input forward FFT |
| `IRFFT` | Real-output inverse FFT |
| `STFT WindowSpec HopLength` | Short-time FT with windowing |
| `MelSpectrogram MelSpec` | Mel-scaled spectrogram |
| `ComplexMul`, `ComplexAdd`, `Magnitude`, `Phase` | Complex arithmetic ops |
<!-- jitml:numerics.spectral:end -->

Owning module: `src/JitML/Numerics/Spectral.hs`.

## Optimizers

<!-- jitml:numerics.optimizers:start -->
| Constructor | Hyperparameters |
|-------------|----------------|
| `SGD` | `lr`, `weightDecay` |
| `MomentumSGD` | `lr`, `momentum`, `weightDecay` |
| `NesterovSGD` | `lr`, `momentum`, `weightDecay` |
| `RMSProp` | `lr`, `alpha`, `eps`, `momentum`, `weightDecay`, `centered` |
| `Adagrad` | `lr`, `eps`, `weightDecay` |
| `Adadelta` | `lr`, `rho`, `eps`, `weightDecay` |
| `Adam` | `lr`, `beta1`, `beta2`, `eps`, `weightDecay` |
| `AdamW` | `lr`, `beta1`, `beta2`, `eps`, `weightDecay` |
| `LAMB` | `lr`, `beta1`, `beta2`, `eps`, `weightDecay` |
| `LARS` | `lr`, `momentum`, `eta`, `weightDecay` |
| `Lion` | `lr`, `beta1`, `beta2`, `weightDecay` |
<!-- jitml:numerics.optimizers:end -->

Owning module: `src/JitML/Numerics/Optimizer.hs`.

## Schedulers

<!-- jitml:numerics.schedulers:start -->
| Constructor | Hyperparameters |
|-------------|----------------|
| `Constant` | `lr` |
| `Linear` | `start`, `end`, `totalSteps` |
| `Cosine` | `start`, `end`, `totalSteps` |
| `CosineWithWarmup` | `warmupSteps`, `peak`, `final`, `totalSteps` |
| `Exponential` | `start`, `gamma`, `totalSteps` |
| `Polynomial` | `start`, `end`, `power`, `totalSteps` |
| `OneCycle` | `peakLr`, `totalSteps`, `pctStart`, `divFactor`, `finalDivFactor` |
| `Piecewise` | ordered `(step, lr)` breakpoints |
<!-- jitml:numerics.schedulers:end -->

Owning module: `src/JitML/Numerics/Scheduler.hs`. History-dependent
`ReduceOnPlateau` behavior lives in callbacks because it consumes evaluation
history rather than only progress.

## Loss Functions

<!-- jitml:numerics.losses:start -->
| Constructor | Hyperparameters |
|-------------|----------------|
| `CrossEntropy` | (none — class count from upstream layer) |
| `BinaryCrossEntropy` | (none) |
| `Focal` | `gamma`, `alpha` |
| `MSE` | (none) |
| `MAE` | (none) |
| `Huber` | `delta` |
| `IoU` | (none) |
| `DiceLoss` | `smooth` |
| `KLDivergence` | (none) |
| `CTCLoss` | `blankIdx` |
| `LabelSmoothedCrossEntropy` | `eps` |
| `ContrastiveLoss` | `margin` |
| `TripletLoss` | `margin` |
| `CustomLoss` | `name`, `registryRef` (escape hatch with explicit registration) |
<!-- jitml:numerics.losses:end -->

Owning module: `src/JitML/Numerics/Loss.hs`.

## Dhall Schemas

`dhall/numerics/Schema.dhall` is the umbrella module re-exporting `Layer`,
`Activation`, `ComplexActivation`, `SpectralOp`, `Optimizer`, `Scheduler`,
`Loss`. `src/JitML/Numerics/Schema.hs` exposes
`decodeNumericsCatalog :: Dhall.Decoder NumericsCatalog`.

`src/JitML/Lint/DhallNumerics.hs` enforces the cross-type audit:

- Every Haskell constructor has a Dhall constructor of the same name.
- Every Dhall constructor has a Haskell decoder.

`jitml lint haskell` runs this lint.

## Worked Example

The worked Dhall example from [../README.md → Concrete Dhall worked
example](../../README.md#concrete-dhall-worked-example) is encoded in
`experiments/sl/mnist-baseline.dhall`, parseable end-to-end with `dhall
resolve` plus `dhall/numerics/Schema.dhall`.

## Cross-References

- [../../README.md → Numerical core](../../README.md#numerical-core)
- [training_workloads.md](training_workloads.md)
- [jit_codegen_architecture.md](jit_codegen_architecture.md)
- [../../DEVELOPMENT_PLAN/phase-6-numerical-core.md](../../DEVELOPMENT_PLAN/phase-6-numerical-core.md)

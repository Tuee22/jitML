# Phase 6: Numerical Core

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-7-jit-codegen-and-substrates.md](phase-7-jit-codegen-and-substrates.md),
[phase-8-supervised-and-rl-framework.md](phase-8-supervised-and-rl-framework.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Stand up the Dhall-typed numerical core: layer catalog (real and
> complex), activations (real and complex), spectral / frequency-domain
> operations, optimizers, schedulers, loss functions, and the Dhall types that
> mirror every Haskell ADT.

## Phase Status

⏸️ **Blocked** on Phase `5` closure. The numerical core is a typed catalog
consumed by the daemon's training and inference loops; it has no runtime
behaviour of its own beyond shape validation and Dhall round-tripping. Per-
substrate JIT codegen (Phase `7`) consumes this catalog.

## Phase Summary

This phase delivers the typed numerical core — every Haskell ADT for layers,
activations, spectral ops, optimizers, schedulers, and losses, plus matching
Dhall schemas. The catalog is the source of truth for what experiments can
declare; the JIT codegen drivers (Phase `7`) consume the catalog to produce
substrate-specific kernels. No SL/RL training logic lives here — that is
Phase `8`.

## Sprint 6.1: Layer Catalog (Real and Complex) ⏸️

**Status**: Blocked
**Blocked by**: phase-5
**Implementation**: `src/JitML/Numerics/Layer.hs`,
`src/JitML/Numerics/Layer/Real.hs`,
`src/JitML/Numerics/Layer/Complex.hs`,
`dhall/numerics/Layer.dhall`
**Docs to update**: `documents/engineering/numerical_core.md`

### Objective

Stand up the layer catalog as a closed sum type. Every constructor is the
canonical name used by experiment Dhalls and the JIT codegen drivers.

### Deliverables

- `Layer` GADT enumerating: `Dense`, `Conv1D`, `Conv2D`, `Conv3D`,
  `ConvTranspose1D`, `ConvTranspose2D`, `BatchNorm`, `LayerNorm`, `GroupNorm`,
  `Dropout`, `ResidualBlock`, `MultiHeadAttention`, `MultiQueryAttention`,
  `Embedding`, `PositionalEncoding`, `RMSNorm`, `Pool` (`Max | Avg | LP`),
  `Flatten`, `Reshape`, `Permute`.
- Complex-valued layer variants where applicable: `ComplexDense`,
  `ComplexConv2D`, `ComplexLayerNorm`, `ComplexAttention`.
- Each constructor carries typed shape parameters (input/output dims,
  kernel/stride/dilation, normalisation mode, dropout probability) plus an
  initialisation strategy (`Glorot`, `He`, `Constant`, `Normal`, `Uniform`).
- `dhall/numerics/Layer.dhall` mirrors the Haskell ADT; the Haskell type and
  the Dhall type are kept in sync by Sprint `6.6`.
- The catalog table is generated into
  `documents/engineering/numerical_core.md` under marker key
  `numerics.layers` (Sprint `1.3` registry).

### Validation

1. Every `Layer` constructor decodes from its Dhall encoding and back round-
   trips.
2. `jitml-unit` exercises the property `decode . encode == id` over every
   constructor.
3. The generated catalog table in `numerical_core.md` matches the in-code
   enumeration (Sprint `1.3` `docs check`).

## Sprint 6.2: Activations (Real and Complex) ⏸️

**Status**: Blocked
**Blocked by**: 6.1
**Implementation**: `src/JitML/Numerics/Activation.hs`,
`src/JitML/Numerics/Activation/Real.hs`,
`src/JitML/Numerics/Activation/Complex.hs`,
`dhall/numerics/Activation.dhall`
**Docs to update**: `documents/engineering/numerical_core.md`

### Objective

Enumerate the supported activations, real and complex.

### Deliverables

- `Activation` ADT for real-valued: `ReLU`, `LeakyReLU Double`, `PReLU`,
  `ELU`, `GELU`, `SiLU` (a.k.a. `Swish`), `Tanh`, `Sigmoid`, `Softplus`,
  `Softmax (Maybe Axis)`, `LogSoftmax (Maybe Axis)`, `HardSigmoid`,
  `HardSwish`, `Mish`.
- `ComplexActivation` ADT for complex-valued: `ModReLU Double`, `ZReLU`,
  `ComplexGELU`, `ComplexTanh`, `ComplexSoftmax (Maybe Axis)`.
- Each variant has a Dhall mirror.
- The catalog table is generated into `numerical_core.md` under
  `numerics.activations`.

### Validation

1. Round-trip property holds.
2. Numerical-core docs render the activation table consistently.

## Sprint 6.3: Spectral / Frequency-Domain Operations ⏸️

**Status**: Blocked
**Blocked by**: 6.2
**Implementation**: `src/JitML/Numerics/Spectral.hs`,
`dhall/numerics/Spectral.dhall`
**Docs to update**: `documents/engineering/numerical_core.md`

### Objective

Land first-class spectral operations: FFT, IFFT, RFFT, IRFFT, complex
multiply, complex add, plus the typed `SpectralOp` ADT.

### Deliverables

- `SpectralOp` ADT: `FFT (Maybe Axis)`, `IFFT (Maybe Axis)`, `RFFT`, `IRFFT`,
  `STFT WindowSpec HopLength`, `MelSpectrogram MelSpec`, `ComplexMul`,
  `ComplexAdd`, `Magnitude`, `Phase`.
- Dhall mirror at `dhall/numerics/Spectral.dhall`.
- Generated table under `numerics.spectral`.

### Validation

1. Round-trip property holds.
2. The numerical-core docs render the spectral table consistently.

## Sprint 6.4: Optimizers and Schedulers ⏸️

**Status**: Blocked
**Blocked by**: 6.1
**Implementation**: `src/JitML/Numerics/Optimizer.hs`,
`src/JitML/Numerics/Scheduler.hs`,
`dhall/numerics/Optimizer.dhall`,
`dhall/numerics/Scheduler.dhall`
**Docs to update**: `documents/engineering/numerical_core.md`

### Objective

Enumerate the supported optimizers and learning-rate schedulers.

### Deliverables

- `Optimizer` ADT: `SGD { lr, momentum, nesterov, weightDecay }`,
  `Momentum { lr, momentum }`, `Adam { lr, beta1, beta2, eps, weightDecay }`,
  `AdamW { lr, beta1, beta2, eps, weightDecay }`,
  `RMSProp { lr, alpha, eps, momentum, weightDecay, centered }`,
  `Lion { lr, beta1, beta2, weightDecay }`,
  `Adafactor { lr, beta2Cap, eps1, eps2, clipThreshold, decayRate,
  weightDecay, scaleParameter, relativeStep, warmupInit }`.
- `Scheduler` ADT: `Constant Double`, `Step { startLr, gamma, stepSizeEpochs
  }`, `Cosine { startLr, finalLr, periodEpochs }`,
  `Polynomial { startLr, endLr, power, totalSteps }`,
  `WarmupCosine { warmupSteps, peakLr, finalLr, totalSteps }`,
  `OneCycle { peakLr, totalSteps, pctStart, divFactor, finalDivFactor }`,
  `Plateau { factor, patience, threshold, minLr }`.
- Dhall mirrors.
- Generated tables under `numerics.optimizers` and `numerics.schedulers`.

### Validation

1. Round-trip property holds.
2. The numerical-core docs render both tables consistently.

## Sprint 6.5: Loss Functions ⏸️

**Status**: Blocked
**Blocked by**: 6.1
**Implementation**: `src/JitML/Numerics/Loss.hs`,
`dhall/numerics/Loss.dhall`
**Docs to update**: `documents/engineering/numerical_core.md`

### Objective

Enumerate the supported loss functions.

### Deliverables

- `Loss` ADT: `CrossEntropy`, `BinaryCrossEntropy`,
  `Focal { gamma, alpha }`, `MSE`, `MAE`, `Huber { delta }`, `IoU`,
  `DiceLoss { smooth }`, `KLDivergence`, `CTCLoss { blankIdx }`,
  `LabelSmoothedCrossEntropy { eps }`,
  `ContrastiveLoss { margin }`, `TripletLoss { margin }`,
  `CustomLoss { name, registryRef }` (escape hatch with explicit registration).
- Dhall mirror.
- Generated table under `numerics.losses`.

### Validation

1. Round-trip property holds.
2. The numerical-core docs render the loss table consistently.

## Sprint 6.6: Dhall Schemas and Cross-Type Audit ⏸️

**Status**: Blocked
**Blocked by**: 6.1, 6.2, 6.3, 6.4, 6.5
**Implementation**: `dhall/numerics/`, `src/JitML/Numerics/Schema.hs`,
`src/JitML/Lint/DhallNumerics.hs`
**Docs to update**: `documents/engineering/numerical_core.md`

### Objective

Audit that every Haskell ADT has a Dhall mirror, every Dhall type maps to a
Haskell ADT, and the experiment-Dhall worked example from
[../README.md → Concrete Dhall worked
example](../README.md#concrete-dhall-worked-example) is parseable end-to-end
against the numerical core.

### Deliverables

- `dhall/numerics/Schema.dhall` is the umbrella module re-exporting `Layer`,
  `Activation`, `ComplexActivation`, `SpectralOp`, `Optimizer`, `Scheduler`,
  `Loss`.
- `src/JitML/Numerics/Schema.hs` exposes `decodeNumericsCatalog ::
  Dhall.Decoder NumericsCatalog`.
- `src/JitML/Lint/DhallNumerics.hs` enforces the cross-type audit: every
  Haskell constructor has a Dhall constructor of the same name; every Dhall
  constructor has a Haskell decoder. `jitml lint haskell` runs this lint.
- The worked Dhall example from the README is encoded in `experiments/`
  under `experiments/sl/mnist-baseline.dhall`, parseable with `dhall
  resolve` plus the schema.

### Validation

1. `dhall resolve <experiments/sl/mnist-baseline.dhall>` succeeds.
2. `jitml lint haskell` reports zero numerical-core type drift.
3. The generated catalog tables in `numerical_core.md` are byte-equal across
   `jitml docs generate` runs.

## Doctrine Sections Cited

- [../HASKELL_CLI_TOOL.md → Architecture](../HASKELL_CLI_TOOL.md) (every sprint — typed values for the model graph)
- [../HASKELL_CLI_TOOL.md → Generated Artifacts](../HASKELL_CLI_TOOL.md) (Sprint 6.6 — the catalog tables under `numerics.*` keys)
- [../HASKELL_CLI_TOOL.md → Lint, Format, and Code-Quality Stack](../HASKELL_CLI_TOOL.md) (Sprint 6.6 — the cross-type audit)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/numerical_core.md` — populate the layer / activation
  / spectral / optimizer / scheduler / loss tables (each generated from the
  registry) plus the cross-type audit narrative.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → Numerical Core Inventory` rows move from
  `⏸️ Blocked` through `🔄 Active` to `✅ Done`.
- `experiments/sl/mnist-baseline.dhall` lands under `experiments/` (the
  configuration-as-code surface declared in
  [../README.md → Repository layout (target)](../README.md#repository-layout-target)).

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)

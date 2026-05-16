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

> **Purpose**: Stand up the current local numerical catalog surface — layer
> names, real/complex activation names, spectral / frequency-domain operation
> names, optimizers, schedulers, loss functions, and deterministic catalog
> rendering — plus Dhall mirror lists and the Haskell cross-type audit that
> keeps those lists aligned with the catalog. Rich parameterized constructors
> remain target work.

## Phase Status

✅ **Done** for the local typed catalog surface. The numerical core is a typed
catalog consumed by the daemon's future training and inference loops; it has no
runtime behaviour of its own beyond catalog enumeration and rendering today.
Per-substrate JIT codegen (Phase `7`) consumes this catalog.

### Current Implementation Scope

The current worktree implements the Haskell catalog in
`src/JitML/Numerics/Catalog.hs`: eleven layer constructors, seven activations,
four spectral operations, eleven optimizers, eight schedulers, five losses, and
`renderNumericalCatalog`. It also implements the Dhall mirror list tree at
`dhall/numerics/`, the decoder/validator in `src/JitML/Numerics/Schema.hs`,
and the lint hook in `src/JitML/Lint/DhallNumerics.hs`. It does not yet contain
the richer parameterized constructors described by the target architecture
below.

## Phase Summary

This phase delivers the local Haskell numerical catalog for layers,
activations, spectral ops, optimizers, schedulers, and losses; the Dhall mirror
lists; the Haskell decoder/validator; the lint audit; and the generated catalog
tables. No SL/RL training logic lives here — that is Phase `8`.

## Sprint 6.1: Layer Catalog ✅

**Status**: Done
**Implementation**: `src/JitML/Numerics/Catalog.hs`
**Docs to update**: `documents/engineering/numerical_core.md`

### Objective

Stand up the current local layer catalog as a closed Haskell sum type. Rich
shape parameters and complex layer variants remain target runtime work.

### Deliverables

- `Layer` enumerates the checked-in local catalog: `Dense`, `Conv1D`,
  `Conv2D`, `Conv3D`, `ConvTranspose`, `BatchNorm`, `LayerNorm`, `GroupNorm`,
  `Dropout`, `ResidualBlock`, and `MultiHeadAttention`.
- `layerCatalog` is the implementation source for the local layer list.
- `renderNumericalCatalog` includes the layer list in the deterministic text
  summary consumed by command and documentation surfaces.
- `dhall/numerics/Layer.dhall` mirrors the current constructor names.

### Validation

1. `src/JitML/Numerics/Catalog.hs` exposes the eleven layer constructors named
   above.
2. `renderNumericalCatalog` is deterministic for the current catalog.
3. `jitml-unit` and `jitml lint haskell` validate the Dhall mirror against the
   Haskell catalog.

## Sprint 6.2: Activations (Real and Complex) ✅

**Status**: Done
**Implementation**: `src/JitML/Numerics/Catalog.hs`
**Docs to update**: `documents/engineering/numerical_core.md`

### Objective

Enumerate the supported local activation catalog, including the current
complex-valued activation names.

### Deliverables

- `Activation` enumerates `Relu`, `Gelu`, `Tanh`, `Sigmoid`, `Softmax`,
  `ComplexModRelu`, and `ComplexCardioid`.
- `activationCatalog` is the implementation source for the local activation
  list.
- `renderNumericalCatalog` includes the activation list in the deterministic
  text summary.
- `dhall/numerics/Activation.dhall` mirrors the current constructor names.

### Validation

1. `activationCatalog` contains the seven checked-in activation constructors.
2. `renderNumericalCatalog` renders the activation names deterministically.

## Sprint 6.3: Spectral / Frequency-Domain Operations ✅

**Status**: Done
**Implementation**: `src/JitML/Numerics/Catalog.hs`
**Docs to update**: `documents/engineering/numerical_core.md`

### Objective

Land the current local spectral-operation catalog.

### Deliverables

- `SpectralOp` enumerates `FFT`, `IFFT`, `STFT`, and `DCT`.
- `spectralCatalog` is the implementation source for the local spectral list.
- `renderNumericalCatalog` includes the spectral-operation list.
- `dhall/numerics/SpectralOp.dhall` mirrors the current constructor names.
- Axis-aware spectral operations and complex arithmetic ops remain target work.

### Validation

1. `spectralCatalog` contains the four checked-in spectral constructors.
2. `renderNumericalCatalog` renders the spectral names deterministically.

## Sprint 6.4: Optimizers and Schedulers ✅

**Status**: Done
**Implementation**: `src/JitML/Numerics/Catalog.hs`
**Docs to update**: `documents/engineering/numerical_core.md`

### Objective

Enumerate the current local optimizer and scheduler catalogs.

### Deliverables

- `Optimizer` enumerates `SGD`, `MomentumSGD`, `NesterovSGD`, `RMSProp`,
  `Adagrad`, `Adadelta`, `Adam`, `AdamW`, `LAMB`, `LARS`, and `Lion`.
- `Scheduler` enumerates `Constant`, `Linear`, `Cosine`,
  `CosineWithWarmup`, `Exponential`, `Polynomial`, `OneCycle`, and
  `Piecewise`.
- `optimizerCatalog` and `schedulerCatalog` are the implementation sources for
  the local lists.
- Parameterized optimizer/scheduler records, callback-based
  `ReduceOnPlateau`, and richer optimizer state records remain target work.
- `dhall/numerics/Optimizer.dhall` and `dhall/numerics/Scheduler.dhall` mirror
  the current constructor names.

### Validation

1. `optimizerCatalog` contains the eleven checked-in optimizer constructors.
2. `schedulerCatalog` contains the eight checked-in scheduler constructors.
3. `renderNumericalCatalog` renders both lists deterministically.

## Sprint 6.5: Loss Functions ✅

**Status**: Done
**Implementation**: `src/JitML/Numerics/Catalog.hs`
**Docs to update**: `documents/engineering/numerical_core.md`

### Objective

Enumerate the current local loss-function catalog.

### Deliverables

- `Loss` enumerates `CrossEntropy`, `Focal`, `MSE`, `Huber`, and `IoU`.
- `lossCatalog` is the implementation source for the local loss list.
- `renderNumericalCatalog` includes the loss list in the deterministic text
  summary.
- `dhall/numerics/Loss.dhall` mirrors the current constructor names.
- Parameterized loss constructors and custom-loss registration remain target
  work.

### Validation

1. `lossCatalog` contains the five checked-in loss constructors.
2. `renderNumericalCatalog` renders the loss names deterministically.

## Sprint 6.6: Dhall Schemas and Cross-Type Audit ✅

**Status**: Done
**Implementation**: `src/JitML/Numerics/Catalog.hs`, `experiments/`
**Docs to update**: `documents/engineering/numerical_core.md`

### Objective

Record the local configuration fixtures and Dhall schema mirror that exercise
the current catalog surface.

### Deliverables

- `experiments/mnist.dhall`, `experiments/mnist-tune.dhall`, and
  `experiments/cartpole.dhall` are present as the current configuration-as-code
  fixtures.
- `dhall/numerics/Schema.dhall` re-exports the current constructor-name lists
  for layers, activations, spectral ops, optimizers, schedulers, and losses.
- `src/JitML/Numerics/Schema.hs` decodes the Dhall schema and validates it
  against the Haskell catalog.
- `src/JitML/Lint/DhallNumerics.hs` plugs that audit into `jitml lint haskell`.

### Validation

1. The three current `experiments/*.dhall` fixtures exist in the worktree.
2. The local catalog is renderable through `renderNumericalCatalog`.
3. `cabal test jitml-unit` validates the Dhall schema mirror.
4. `jitml lint haskell` includes the Dhall numerical drift audit.

## Doctrine Sections Cited

- [../HASKELL_CLI_TOOL.md → Architecture](../HASKELL_CLI_TOOL.md) (every sprint — typed values for the model graph)
- [../HASKELL_CLI_TOOL.md → Generated Artifacts](../HASKELL_CLI_TOOL.md) (Sprint 6.6 — the catalog tables under `numerics.*` keys)
- [../HASKELL_CLI_TOOL.md → Lint, Format, and Code-Quality Stack](../HASKELL_CLI_TOOL.md) (Sprint 6.6 — the cross-type audit)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/numerical_core.md` — current local layer /
  activation / spectral / optimizer / scheduler / loss catalog summary, active
  generated tables, Dhall mirrors, and cross-type audit narrative.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → Numerical Core Inventory` rows remain aligned with
  the aggregate catalog in `src/JitML/Numerics/Catalog.hs`.
- `experiments/mnist.dhall`, `experiments/mnist-tune.dhall`, and
  `experiments/cartpole.dhall` land under `experiments/` as the
  configuration-as-code fixtures for the local catalog surface.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)

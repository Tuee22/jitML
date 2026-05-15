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

✅ **Done** for the local typed catalog surface. The numerical core is a typed
catalog consumed by the daemon's future training and inference loops; it has no
runtime behaviour of its own beyond catalog enumeration and rendering today.
Per-substrate JIT codegen (Phase `7`) consumes this catalog.

### Current Implementation Scope

The current worktree implements the Haskell catalog in
`src/JitML/Numerics/Catalog.hs`: eleven layer constructors, seven activations,
four spectral operations, eleven optimizers, eight schedulers, five losses, and
`renderNumericalCatalog`. It does not yet contain the `dhall/numerics/*` schema
tree, Dhall decoders, generated numerical documentation tables, or rich
parameterized constructors described by the target architecture below.

## Phase Summary

This phase delivers the local Haskell numerical catalog for layers,
activations, spectral ops, optimizers, schedulers, and losses. Matching Dhall
schemas and generated catalog tables are target documentation/runtime work. No
SL/RL training logic lives here — that is Phase `8`.

## Sprint 6.1: Layer Catalog ✅

**Status**: Done
**Implementation**: `src/JitML/Numerics/Catalog.hs`
**Docs to update**: `documents/engineering/numerical_core.md`

### Objective

Stand up the current local layer catalog as a closed Haskell sum type. Rich
shape parameters, complex layer variants, Dhall mirrors, and generated catalog
tables remain target runtime/documentation work.

### Deliverables

- `Layer` enumerates the checked-in local catalog: `Dense`, `Conv1D`,
  `Conv2D`, `Conv3D`, `ConvTranspose`, `BatchNorm`, `LayerNorm`, `GroupNorm`,
  `Dropout`, `ResidualBlock`, and `MultiHeadAttention`.
- `layerCatalog` is the implementation source for the local layer list.
- `renderNumericalCatalog` includes the layer list in the deterministic text
  summary consumed by command and documentation surfaces.
- Target work keeps the richer parameterized constructors and Dhall mirrors
  out of the current `Done` claim until those files exist.

### Validation

1. `src/JitML/Numerics/Catalog.hs` exposes the eleven layer constructors named
   above.
2. `renderNumericalCatalog` is deterministic for the current catalog.
3. The target Dhall decode/encode audit remains outside the current local
   closure because no `dhall/numerics/` schema tree exists yet.

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
- Separate parameterized real/complex activation ADTs and Dhall mirrors remain
  target work.

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
- Axis-aware spectral operations, complex arithmetic ops, Dhall mirrors, and
  generated numerical tables remain target work.

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
  `ReduceOnPlateau`, Dhall mirrors, and generated catalog tables remain target
  work.

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
- Parameterized loss constructors, custom-loss registration, Dhall mirrors, and
  generated catalog tables remain target work.

### Validation

1. `lossCatalog` contains the five checked-in loss constructors.
2. `renderNumericalCatalog` renders the loss names deterministically.

## Sprint 6.6: Dhall Schemas and Cross-Type Audit ✅

**Status**: Done
**Implementation**: `src/JitML/Numerics/Catalog.hs`, `experiments/`
**Docs to update**: `documents/engineering/numerical_core.md`

### Objective

Record the local configuration fixtures that exercise the current catalog
surface. Full Dhall schema mirroring and decoder-based cross-type audit remain
target work.

### Deliverables

- `experiments/mnist.dhall`, `experiments/mnist-tune.dhall`, and
  `experiments/cartpole.dhall` are present as the current configuration-as-code
  fixtures.
- The current Haskell catalog remains the only implemented numerical schema.
- `dhall/numerics/`, `src/JitML/Numerics/Schema.hs`, and
  `src/JitML/Lint/DhallNumerics.hs` do not exist in the current tree and remain
  target work.

### Validation

1. The three current `experiments/*.dhall` fixtures exist in the worktree.
2. The local catalog is renderable through `renderNumericalCatalog`.
3. Dhall schema round-trip validation is not claimed until the schema and
   decoder modules land.

## Doctrine Sections Cited

- [../HASKELL_CLI_TOOL.md → Architecture](../HASKELL_CLI_TOOL.md) (every sprint — typed values for the model graph)
- [../HASKELL_CLI_TOOL.md → Generated Artifacts](../HASKELL_CLI_TOOL.md) (Sprint 6.6 — the catalog tables under `numerics.*` keys)
- [../HASKELL_CLI_TOOL.md → Lint, Format, and Code-Quality Stack](../HASKELL_CLI_TOOL.md) (Sprint 6.6 — the cross-type audit)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/numerical_core.md` — current local layer /
  activation / spectral / optimizer / scheduler / loss catalog summary; target
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

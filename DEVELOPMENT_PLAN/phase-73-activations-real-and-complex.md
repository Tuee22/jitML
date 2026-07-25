# Phase 73: Activations (Real and Complex)

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Activations (Real and Complex). Single-session phase migrated from legacy Sprint 6.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 73.1: Activations (Real and Complex) [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Numerics/Catalog.hs`
**Docs to update**: `documents/engineering/numerical_core.md`

### Objective

Enumerate the activation catalog, including the complex-valued
activation names.

### Deliverables

- `Activation` enumerates `Relu`, `LeakyRelu`, `Elu`, `Silu`, `Gelu`,
  `Tanh`, `Sigmoid`, `Softmax`, `ComplexModRelu`, `ComplexCardioid`, and
  `ComplexZRelu`.
- `activationCatalog` is the implementation source for the activation
  list.
- `renderNumericalCatalog` includes the activation list in the deterministic
  text summary.
- `dhall/numerics/Activation.dhall` mirrors the current constructor names.

### Validation

1. `activationCatalog` contains the eleven checked-in activation constructors.
2. `renderNumericalCatalog` renders the activation names deterministically.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

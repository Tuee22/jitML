# Phase 72: Layer Catalog

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Layer Catalog. Single-session phase migrated from legacy Sprint 6.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 72.1: Layer Catalog [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Numerics/Catalog.hs`
**Docs to update**: `documents/engineering/numerical_core.md`

### Objective

Stand up the layer catalog as a closed Haskell sum type including
embedding, attention, rotary-position, and complex layer constructors.

### Deliverables

- `Layer` enumerates the catalog: `Dense`, `Embedding`,
  `Conv1D`, `Conv2D`, `Conv3D`, `ConvTranspose`, `ComplexDense`,
  `ComplexConv2D`, `BatchNorm`, `LayerNorm`, `GroupNorm`, `Dropout`,
  `ResidualBlock`, `ScaledDotProductAttention`, `MultiHeadAttention`, and
  `RotaryPositionalEmbedding`.
- `layerCatalog` is the implementation source for the layer list.
- `renderNumericalCatalog` includes the layer list in the deterministic text
  summary consumed by command and documentation surfaces.
- `dhall/numerics/Layer.dhall` mirrors the current constructor names.

### Validation

1. `src/JitML/Numerics/Catalog.hs` exposes the sixteen layer constructors named
   above.
2. `renderNumericalCatalog` is deterministic for the current catalog.
3. `jitml-unit` and `jitml lint haskell` validate the Dhall mirror against the
   Haskell catalog.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

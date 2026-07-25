# Phase 74: Spectral / Frequency-Domain Operations

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Spectral / Frequency-Domain Operations. Single-session phase migrated from legacy Sprint 6.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 74.1: Spectral / Frequency-Domain Operations [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Numerics/Catalog.hs`
**Docs to update**: `documents/engineering/numerical_core.md`

### Objective

Land the spectral-operation catalog.

### Deliverables

- `SpectralOp` enumerates `FFT`, `FFTAlongAxis`, `IFFT`, `IFFTAlongAxis`,
  `RFFT`, `IRFFT`, `STFT`, `DCT`, `ComplexConjugate`, and `ComplexMatMul`.
- `spectralCatalog` is the implementation source for the spectral list.
- `renderNumericalCatalog` includes the spectral-operation list.
- `dhall/numerics/SpectralOp.dhall` mirrors the current constructor names.

### Validation

1. `spectralCatalog` contains the ten checked-in spectral constructors.
2. `renderNumericalCatalog` renders the spectral names deterministically.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

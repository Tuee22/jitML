# Phase 76: Loss Functions

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Loss Functions. Single-session phase migrated from legacy Sprint 6.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Current execution ownership

**Historical record; no current execution gate.** Phases 1–289 retain their
original contracts, statuses and receipts below. Their former order, dependencies
and current-sounding statements are historical. They do not gate the new
[numerical execution sequence](ordered-execution-plan.md). No historical failure
is erased and no historical Done is promoted to current qualification.

The original recorded scope remains historical; no new obligation or current
closure is inferred from its prior status. A discovered defect reopens its
current successor owner under the [plan standards](development_plan_standards.md).

## Historical plan and evidence

## Phase State

✅ **Done**.

## Sprint 76.1: Loss Functions [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Numerics/Catalog.hs`
**Docs to update**: `documents/engineering/numerical_core.md`

### Objective

Enumerate the loss-function catalog.

### Deliverables

- `Loss` enumerates `CrossEntropy`, `BinaryCrossEntropy`,
  `SparseCrossEntropy`, `Focal`, `MSE`, `Huber`, `IoU`, `Dice`, `KLDiv`, and
  `Contrastive`.
- `lossCatalog` is the implementation source for the loss list.
- `renderNumericalCatalog` includes the loss list in the deterministic text
  summary.
- `dhall/numerics/Loss.dhall` mirrors the current constructor names.
- Parameterized loss records and custom-loss registration remain model-schema
  work.

### Validation

1. `lossCatalog` contains the ten checked-in loss constructors.
2. `renderNumericalCatalog` renders the loss names deterministically.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

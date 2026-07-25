# Phase 75: Optimizers and Schedulers

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Optimizers and Schedulers. Single-session phase migrated from legacy Sprint 6.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 75.1: Optimizers and Schedulers [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Numerics/Catalog.hs`
**Docs to update**: `documents/engineering/numerical_core.md`

### Objective

Enumerate the optimizer and scheduler catalogs.

### Deliverables

- `Optimizer` enumerates `SGD`, `MomentumSGD`, `NesterovSGD`, `RMSProp`,
  `Adagrad`, `Adadelta`, `Adam`, `AdamW`, `LAMB`, `LARS`, `Lion`,
  `AdaFactor`, and `Shampoo`.
- `Scheduler` enumerates `Constant`, `Linear`, `Cosine`,
  `CosineWithWarmup`, `Exponential`, `Polynomial`, `OneCycle`, and
  `Piecewise`, plus `ReduceOnPlateau` as the callback-driven scheduler entry.
- `optimizerCatalog` and `schedulerCatalog` are the implementation
  sources for the lists.
- Parameterized optimizer/scheduler records and richer optimizer state records
  remain model-schema work.
- `dhall/numerics/Optimizer.dhall` and `dhall/numerics/Scheduler.dhall` mirror
  the current constructor names.

### Validation

1. `optimizerCatalog` contains the thirteen checked-in optimizer constructors.
2. `schedulerCatalog` contains the nine checked-in scheduler constructors.
3. `renderNumericalCatalog` renders both lists deterministically.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

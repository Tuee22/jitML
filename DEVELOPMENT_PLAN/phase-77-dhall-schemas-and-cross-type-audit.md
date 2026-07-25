# Phase 77: Dhall Schemas and Cross-Type Audit

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Dhall Schemas and Cross-Type Audit. Single-session phase migrated from legacy Sprint 6.6 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 77.1: Dhall Schemas and Cross-Type Audit [✅ Done]

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
2. The catalog is renderable through `renderNumericalCatalog`.
3. `cabal test jitml-unit` validates the Dhall schema mirror.
4. `jitml lint haskell` includes the Dhall numerical drift audit.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

# Phase 77: Dhall Schemas and Cross-Type Audit

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Dhall Schemas and Cross-Type Audit. Single-session phase migrated from legacy Sprint 6.6 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

🔄 **Active** (2026-08-12). Reopened under standards rule `L`. The cross-type audit compares
`Catalog.Layer` against `dhall/numerics/Layer.dhall` — two hand-maintained
`List Text` name lists, neither of which reaches execution — while the executed
`LayerOp` has no Dhall mirror and no audit. The project doctrine in
[../README.md](../README.md) states that every layer is a first-class Dhall
constructor and networks are composed as arbitrary DAGs over those primitives; the
implemented experiment record carries four scalars and names a hardcoded Haskell
architecture. That is a doctrine gap, and rule `L` forbids closing it silently.

## Sprint 77.1: Dhall Schemas and Cross-Type Audit [🔄 Active]

**Status**: Active
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

### Remaining Work

- Express the layer vocabulary as parameterised Dhall constructors reflected off the
  real decoder with `Dhall.expected`, the pattern already proven for `BootConfig`
  and `dhall/run/Schema.dhall`, so the schema and the Haskell type cannot drift.
- Extend the cross-type audit to the executed `LayerOp`, not only `Catalog.Layer`.
- Keep `substrate` out of the ML DSL: it is currently absent from every ML-describing
  Dhall file and belongs on the CLI/plan seam.
- This sprint implements the doctrine section
  `Generated Artifacts → The generated-section registry`.

### Historical Validation

Evidence for the surface this sprint actually exercised before the 2026-08-12 reopen:

> ✅ **Done**.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

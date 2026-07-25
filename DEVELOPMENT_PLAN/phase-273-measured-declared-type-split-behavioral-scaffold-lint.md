# Phase 273: Measured/Declared Type Split & Behavioral Scaffold Lint

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Measured/Declared Type Split & Behavioral Scaffold Lint. Single-session phase migrated from legacy Sprint 32.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 273.1: Measured/Declared Type Split & Behavioral Scaffold Lint [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Product/Matrix.hs`, `src/JitML/Lint/ProductTruth.hs`, `src/JitML/Test/Report.hs`, `src/JitML/Web/Contracts.hs`, `test/unit/Main.hs`
**Docs to update**: `../documents/engineering/product_completion_contract.md`, `../documents/engineering/purescript_frontend.md`, `system-components.md`

### Objective

A stand-in is typed `Declared` and cannot be reported as real; the scaffold lint is a
behavioral detector, not a name denylist.

### Deliverables

- A `Measured` vs `Declared` metric type and a `RealArchitecture` vs `MlpApproximation`
  distinction carried on `ProductRow`, surfaced in the report card and demo so an
  approximate row is visibly marked.
- The scaffold lint asks "does this product function's output depend on the trained
  weights?" rather than matching fossil names; the `FutureOwner` exemption is deleted.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

- Implemented the type split and behavioral lint.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

# Phase 230: Matrix Parity

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Matrix Parity. Single-session phase migrated from legacy Sprint 22.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 230.1: Matrix Parity [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Product/Matrix.hs`, `src/JitML/SL/Canonicals.hs`, `src/JitML/RL/ConvergenceThresholds.hs`, `test/unit/Main.hs`
**Docs to update**: `../README.md`, `../documents/engineering/training_workloads.md`

### Objective

The documented matrix and the typed registry compare equal in both directions.
README supervised rows, README reinforcement-learning environment rows, the RL
convergence algorithm/environment rows, AlphaZero games, and the tuning/demo
rows each resolve to exactly one `ProductRow` `rowId`, and every registry row is
documented.

### Deliverables

- A parity test compares the README supervised/reinforcement-learning/AlphaZero/
  tuning rows against `Product.Matrix` `rowId`s and fails on any documented row
  missing from the registry, any registry row missing from the docs, and any
  generated PureScript matrix constant that diverges from the registry.
- Missing reinforcement-learning environments (`Acrobot`, `GridWorld`,
  `Pendulum`) are explicit parity failures until a later real-RL-model phase
  implements them or they are typed as non-product rows; the parity test names
  each missing environment rather than passing vacuously.
- A row that is research-only or optional is typed as a non-product row and
  cannot appear in the product matrix, and mismatched algorithm/environment
  pairings surface as named failures.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

**Result (2026-07-02)**:
- `docker compose run --rm jitml jitml test jitml-unit --linux-cpu` — passed,
  261 / 261 tests.
- `docker compose run --rm jitml jitml docs check` — passed.
- `docker compose run --rm jitml jitml check-code` — passed.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

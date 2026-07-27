# Phase 241: Literal Architectures - Dense, MLP, LeNet

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Literal Architectures - Dense, MLP, LeNet. Single-session phase migrated from legacy Sprint 24.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 240 (Sprint 240.1).

## Sprint 241.1: Literal Architectures - Dense, MLP, LeNet [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/SL/Architecture.hs`, `src/JitML/Product/Matrix.hs`, `test/sl-canonicals/Main.hs`
**Blocked by**: Sprint `240.1`
**Docs to update**: `../documents/engineering/training_workloads.md`, `../documents/engineering/numerical_core.md`, `../README.md`

### Objective

The Dense classifier, the deep MLP with BatchNorm and Dropout, LeNet-5, and the
tabular/regression MLP are each constructed as literal layer graphs over the
Phase `233` typed layer engine, so each implemented model is its named
architecture rather than a shared flat topology standing in for many rows.

### Deliverables

- The Dense classifier, the deep MLP with BatchNorm and Dropout, LeNet-5, and the
  tabular/regression MLP are each built in `src/JitML/SL/Architecture.hs` as
  literal layer graphs with the documented layer counts, channel widths,
  normalization (BatchNorm), Dropout, and Conv2D/pooling structure.
- Each of these supervised rows in `src/JitML/Product/Matrix.hs` binds to its
  constructing function and records the concrete architectural features it claims
  (BatchNorm, Dropout, Conv2D).
- A test rejects any of these rows whose documented feature set exceeds the
  implemented layer graph; no simplified topology satisfies a row naming
  BatchNorm, Dropout, or Conv2D.

### Remaining Work

- Implement the Dense, deep-MLP, LeNet-5, and tabular-MLP rows as their literal
  named architectures on the typed `LayerGraph` IR (trained via Phase `238`), including
  real convolution, pooling, and BatchNorm/Dropout structure rather than a shared
  flat approximation.
- Bind the registry's claimed features to that executed graph, and make a
  simplified or mislabeled topology fail the production-path test.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Historical Validation

Historical validation: `docker compose run --rm jitml jitml test
jitml-sl-canonicals --linux-cpu` passed 28 / 28 on 2026-07-02, including the
ProductRow feature-parity, literal topology block-count, simplified-topology
negative case, and live SL materialization/training tests. `docker compose run
--rm jitml jitml test jitml-unit --linux-cpu` passed 270 / 270, `jitml docs
check` passed, and `docker compose run --rm jitml cabal run exe:jitml --
check-code` passed after formatting the Sprint `24.1` Haskell edits.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

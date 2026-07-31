# Phase 242: Literal Architectures - Dense, MLP, LeNet

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Literal Architectures - Dense, MLP, LeNet. Single-session phase migrated from legacy Sprint 24.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** (closed 2026-07-30; gate-validated on the live linux-cpu cluster).
The Dense classifier, the deep MLP with BatchNorm and Dropout, LeNet-5
(Conv2D + pooling), and the tabular/regression MLP are each built as literal
layer graphs over the Phase `233` typed layer engine, trained on the Phase `241`
device kernels; each row binds to its constructing function and feature parity is
enforced (a simplified or mislabeled topology fails the production-path test).

## Sprint 242.1: Literal Architectures - Dense, MLP, LeNet [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/SL/Architecture.hs`, `src/JitML/Product/Matrix.hs`, `test/sl-canonicals/Main.hs`
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

### Validation

```bash
docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

Validated 2026-07-30 (container `jitml:local`, live linux-cpu cluster):
jitml-sl-canonicals 36/36 (incl. the feature-parity and simplified-topology
negative cases and the all-eleven trained==Store-loaded V2 parity), jitml-unit
passed with 0 failures, `jitml check-code` ok, `jitml docs check` ok, and
`jitml internal train-and-publish-product-rows --linux-cpu` exit 0 with 55/55
admitted.

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

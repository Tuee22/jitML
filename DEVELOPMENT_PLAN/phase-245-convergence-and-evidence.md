# Phase 245: Convergence and Evidence

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Convergence and Evidence. Single-session phase migrated from legacy Sprint 24.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 244 (Sprint 244.1).

## Sprint 245.1: Convergence and Evidence [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `test/sl-canonicals/Main.hs`, `src/JitML/Test/RowAssertions.hs`
**Blocked by**: Sprint `244.1`
**Docs to update**: `../documents/engineering/training_metrics_and_splits.md`, `../documents/engineering/numerical_core.md`

### Objective

Each supervised row trains a real train/validation/test split to its
literature-anchored convergence bar and records machine-checkable learning
evidence, so a row cannot pass on a static, degenerate, or smoke-threshold run.

### Deliverables

- Each supervised row records a deterministic initial-weight hash, final-weight
  hash, update count, examples seen, and throughput (examples/sec).
- Classification rows optimize real cross-entropy; regression rows optimize real
  MSE and report RMSE — `1 - accuracy` is not a loss.
- Training uses a real three-way split and the reported figure is the held-out
  test metric, which clears `median(k=5) >= literature_target - slack`.
- `src/JitML/Test/RowAssertions.hs` fails a row when final weights equal
  initialization, gradients are zero or NaN, or the row clears only a smoke
  threshold; a deliberately underpowered 2-step model FAILS its bar.

### Remaining Work

- Train and measure each literal architecture graph (Phases `242`–`244`) from its
  real random initialization against the frozen external bar; evidence from the
  replaced approximation cannot be reused.
- **Re-baseline the six attention/token-mix `slCohortThresholds` vision bars**:
  the correct IR attention (multi-head + `W_O` + residual, affine LayerNorm)
  shifts every median, so re-measure the six vision rows on the live `linux-cpu`
  cluster (row-parallel across cores) and re-confirm the anti-vacuity invariant.
- Prove exact train/validation/test partitioning, train-only fitted regression
  statistics, finite learning, nonzero weight movement, and observed budgets
  for the graph that produced each metric.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
```

### Historical Validation

Historical validation: `docker compose run --rm jitml jitml test
jitml-sl-canonicals --linux-cpu` passed 31 / 31 on 2026-07-02, including the
measured supervised row evidence assertion, invalid/smoke evidence rejection,
and underpowered two-step negative case. `docker compose run --rm jitml jitml
test jitml-integration --linux-cpu` passed 79 / 79 against the live linux-cpu
cluster. `jitml docs check` and `jitml check-code` passed after the Sprint
`24.4` module/docs update.

2026-07-05 realness-audit finding, closed 2026-07-06: the recorded convergence, weight-update,
and learning-evidence figures are all measured on the residual-MLP that
`layersForFamily` trains, not on the named convolutional/attention architecture,
and the bar each row clears is self-authored rather than a frozen external
literature constant — so a passing row does not demonstrate the documented model
learning.

### Closure Evidence

- **Closed Exit-Definition obligation**: each row's held-out convergence metric
  must be *measured on the real named architecture* and cleared against a frozen
  external literature bar, not on the shared flattened-pixel residual-MLP against
  a self-authored threshold.
- **Closing validation**: the per-model `jitml-model-convergence` suite (Phase
  `33`,
  [phase-33-per-model-convergence-and-inference-tests.md](README.md#legacy-to-new-phase-map)),
  which trains each `ProductRow` from a real random init through the production
  device seam and asserts the measured held-out test metric ≥ the Phase `32`
  `ExternalBars` target, must pass for every supervised row via
  `docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu`.

2026-07-10 closure: the standing `jitml-model-convergence --linux-cpu` gate
passed **111 / 111**, including the deep-SL rows measured on the widened
architecture.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

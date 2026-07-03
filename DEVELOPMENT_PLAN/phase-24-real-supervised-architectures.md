# Phase 24: Real Supervised Architectures

**Status**: Done
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-23-general-differentiable-layer-engine.md](phase-23-general-differentiable-layer-engine.md), [phase-25-real-rl-algorithms-and-environments.md](phase-25-real-rl-algorithms-and-environments.md), [../documents/engineering/training_workloads.md](../documents/engineering/training_workloads.md), [../documents/engineering/training_metrics_and_splits.md](../documents/engineering/training_metrics_and_splits.md), [../documents/engineering/checkpoint_format.md](../documents/engineering/checkpoint_format.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md)
**Generated sections**: none

> **Purpose**: Every canonical supervised row is its literal named architecture,
> assembled from the Phase `23` layer engine, and trains to its
> literature-anchored convergence bar on `linux-cpu`.

## Phase State

✅ **Done**. Phase `23` is Done; Sprints `24.1` and `24.2` completed literal
supervised architecture topology, per-row feature parity, convergence,
weight-update, and learning-evidence gates. Sprint `24.3` completed supervised
`CompletedTraining` manifests, graph/layout checkpoint evidence, and
fail-closed inference rejection coverage.

**Validation substrate**: `linux-cpu` only.

## Objective

Every documented supervised-learning row is its literal named architecture, built
as a typed layer graph over the Phase `23` layer engine: LeNet-5, a deep MLP with
BatchNorm and Dropout, a small ResNet, ResNet-20, ResNet-56, WideResNet-28-10, a
small ViT, ResNet-50, and the tabular MLP. No simplified topology satisfies a row
that names BatchNorm, Dropout, Conv2D, ResNet, WideResNet, ViT, or GroupNorm — the
implemented block counts, widths, residual connections, normalization, and
attention match the documented model. Each row trains on a real three-way split
with real losses (cross-entropy for classification, MSE/RMSE for regression),
records deterministic init/final weight hashes, update count, examples seen, and
throughput, and clears `median(k=5) >= literature_target - slack`. Each row writes
an inference-eligible `CompletedTraining` checkpoint, and partial, synthetic, or
untrained supervised manifests are rejected.

## Sprint 24.1: Literal Architectures [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/SL/Architecture.hs`, `src/JitML/Product/Matrix.hs`, `test/sl-canonicals/Main.hs`
**Docs to update**: `../documents/engineering/training_workloads.md`, `../documents/engineering/numerical_core.md`, `../README.md`

### Objective

Every supervised `ProductRow` is constructed as a literal layer graph over the
Phase `23` typed layer engine, so the implemented model is the named architecture
rather than a shared flat topology standing in for many rows.

### Deliverables

- LeNet-5, the deep MLP with BatchNorm and Dropout, the small ResNet, ResNet-20,
  ResNet-56, WideResNet-28-10, the small ViT, ResNet-50, and the tabular MLP are
  each built in `src/JitML/SL/Architecture.hs` as literal layer graphs with the
  documented block counts, channel widths, residual connections, normalization
  (BatchNorm / GroupNorm), Dropout, Conv2D/pooling, and attention blocks.
- Each supervised row in `src/JitML/Product/Matrix.hs` binds to the constructing
  function and records the concrete architectural features it claims (BatchNorm,
  Dropout, Conv2D, GroupNorm, residual, attention).
- A test rejects any row whose documented feature set exceeds the implemented
  layer graph; no simplified topology satisfies a row naming BatchNorm, Dropout,
  Conv2D, ResNet, WideResNet, ViT, or GroupNorm.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

Current validation: `docker compose run --rm jitml jitml test
jitml-sl-canonicals --linux-cpu` passed 28 / 28 on 2026-07-02, including the
ProductRow feature-parity, literal topology block-count, simplified-topology
negative case, and live SL materialization/training tests. `docker compose run
--rm jitml jitml test jitml-unit --linux-cpu` passed 270 / 270, `jitml docs
check` passed, and `docker compose run --rm jitml cabal run exe:jitml --
check-code` passed after formatting the Sprint `24.1` Haskell edits.

### Remaining Work

None.

## Sprint 24.2: Convergence and Evidence [✅ Done]

**Status**: Done
**Implementation**: `test/sl-canonicals/Main.hs`, `src/JitML/Test/RowAssertions.hs`
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

### Validation

```bash
docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
```

Current validation: `docker compose run --rm jitml jitml test
jitml-sl-canonicals --linux-cpu` passed 31 / 31 on 2026-07-02, including the
measured supervised row evidence assertion, invalid/smoke evidence rejection,
and underpowered two-step negative case. `docker compose run --rm jitml jitml
test jitml-integration --linux-cpu` passed 79 / 79 against the live linux-cpu
cluster. `jitml docs check` and `jitml check-code` passed after the Sprint
`24.2` module/docs update.

### Remaining Work

None.

## Sprint 24.3: CompletedTraining SL Manifests [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Checkpoint/`, `test/integration/Main.hs`
**Docs to update**: `../documents/engineering/checkpoint_format.md`

### Objective

Every supervised row writes an inference-eligible checkpoint whose manifest proves
completed training, and the inference read path rejects any partial, synthetic, or
untrained supervised manifest.

### Deliverables

- Every supervised row writes a checkpoint manifest carrying `CompletedTraining`,
  convergence metrics, dataset SHA evidence, and weight-delta evidence.
- Inference rejects partial, synthetic, or untrained supervised manifests.
- The checkpoint reader verifies shape and layout metadata for every supervised
  family (LeNet-5, MLP, ResNet variants, WideResNet, ViT, tabular MLP).

### Validation

```bash
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu
docker compose run --rm jitml jitml check-code
```

Current validation: `docker compose run --rm jitml jitml test
jitml-integration --linux-cpu` passed 81 / 81 on 2026-07-02, including the
supervised completed-manifest graph/layout/evidence cases and fail-closed
partial/synthetic/untrained/malformed manifest loader cases. `docker compose
run --rm jitml jitml test jitml-sl-canonicals --linux-cpu` passed 31 / 31,
including the live MNIST and all-canonical-row supervised materialization and
training checks. `docker compose run --rm jitml jitml check-code` passed after
formatting the Sprint `24.3` integration test wrapping.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/training_workloads.md` — literal supervised
  architectures assembled over the Phase `23` layer engine.
- `documents/engineering/training_metrics_and_splits.md` — three-way splits, real
  cross-entropy / MSE-RMSE losses, and literature-anchored convergence bars.
- `documents/engineering/numerical_core.md` — the layer and kernel primitives the
  literal architectures compose.
- `documents/engineering/checkpoint_format.md` — supervised `CompletedTraining`
  manifest fields and inference-eligibility gates.

**Product docs to create/update:**
- `README.md` — canonical supervised learning problems reflect the literal
  implemented architectures.

**Cross-references to add:**
- Add this phase to `README.md`, `00-overview.md`, `system-components.md`, and
  `development_plan_standards.md`.
- Link supervised convergence and checkpoint evidence from
  `../documents/engineering/product_completion_contract.md`.

# Phase 33: Per-Model Convergence & Inference-Performance Tests

**Status**: Done
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-32-external-truth-realness-harness.md](phase-32-external-truth-realness-harness.md), [phase-34-plan-truth-governance.md](phase-34-plan-truth-governance.md), [../README.md](../README.md), [../documents/engineering/training_metrics_and_splits.md](../documents/engineering/training_metrics_and_splits.md), [../documents/engineering/unit_testing_policy.md](../documents/engineering/unit_testing_policy.md)
**Generated sections**: none

> **Purpose**: Give every product row a model-specific integration test that trains
> the model from a real random initialization and asserts both a **measured**
> convergence metric against its external bar and a **non-wall-clock inference
> performance** metric — so a row is closed by demonstrated learning and inference,
> never by a declared constant or an artifact-read.

## Phase State

✅ **Done**. The reopened Phase `28` found that the per-model integration tests
were artifact-readers, not training drivers, and that the "measured" reward was a
scripted expert controller. This phase installs the standing per-model measurement
suite that consumes the Phase `32` external bars and negative-control primitives. It
depends on Phases `24`–`28` (real models) and Phase `32` (the grader).

**Validation substrate**: `linux-cpu` only.

## Objective

A `jitml-model-convergence` stanza owns one case per `ProductRow`, enumerated from the
registry so coverage cannot silently drop. Each case trains the row's model from a
real random init through the production device seam and asserts: (1) the measured
convergence metric clears the row's external bar (`Phase 32` `ExternalBars`) — median
over `k` seeds for RL, held-out test split for SL, arena win-margin for AlphaZero; and
(2) a non-wall-clock inference-performance metric clears a committed floor (SL
examples/sec throughput; RL sample-efficiency / env-steps-to-threshold), reproduced
bit-identically on a same-seed re-run. Rows whose full literature run is impractical on
`linux-cpu` are typed `Declared` (Phase `32`) until a real run exists — never faked.

## Sprint 33.1: Per-Model Measured Convergence [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Test/RowAssertions.hs`, `test/model-convergence/Main.hs`, `jitml.cabal`
**Docs to update**: `../documents/engineering/training_metrics_and_splits.md`, `../documents/engineering/unit_testing_policy.md`, `system-components.md`

### Objective

Every SL/RL/AlphaZero product row has a case that trains from a real random init and
asserts the measured metric ≥ the external bar, feeding the already-sound
`RowAssertions` helpers with real training output rather than synthetic fixtures.

### Deliverables

- One `jitml-model-convergence` case per `ProductRow`, enumerated from
  `JitML.Product.Matrix.allProductRows`; a missing case fails the coverage assertion.
- SL: train through `JitML.SL.Architecture` on the real staged dataset (held-out test
  split); assert `assertSupervisedRowEvidence` against the measured test metric and a
  real, decreasing loss trajectory.
- RL: train the policy, evaluate the **trained policy** (never the removed expert
  controller), assert `assertRlRowEvidence` with `rleSyntheticTransitionEvidence = False`
  and median-over-`k`-seeds ≥ external bar.
- AlphaZero: real multi-generation self-play + full-`maxPlies` arena; assert
  `assertAlphaZeroRowEvidence` with a strict win-margin.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

- Implemented the row-complete model-convergence stanza; `docker compose run --rm jitml env JITML_SUBSTRATE=linux-cpu cabal test jitml-model-convergence --test-options='--hide-successes --color=never'` passed 111/111 on 2026-07-06.

## Sprint 33.2: Inference-Performance & Determinism [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Test/RowAssertions.hs`, `test/model-convergence/Main.hs`, `src/JitML/Product/ExternalBars.hs`
**Docs to update**: `../documents/engineering/training_metrics_and_splits.md`, `system-components.md`

### Objective

Every row reports a non-wall-clock inference-performance metric against a committed
floor, reproduced bit-identically on re-run.

### Deliverables

- SL rows assert examples/sec throughput ≥ floor; RL rows assert
  env-steps-to-threshold ≤ ceiling (sample efficiency); both from real inference on the
  trained artifact.
- A same-seed re-run reproduces the metric bit-identically (determinism contract).
- The performance floors live in `ExternalBars.hs`, never derived from the measured
  value.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

- Implemented the inference-performance assertions and floors.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/training_metrics_and_splits.md` — the per-model measured
  convergence + inference-performance contract; RL reward is a trained-policy rollout.
- `documents/engineering/unit_testing_policy.md` — ownership of the
  `jitml-model-convergence` stanza.

**Product docs to create/update:**
- `README.md` — the `Convergence and determinism checks for RL` and
  `Canonical supervised learning problems` sections reference the per-model suite.

**Cross-references to add:**
- Add this phase to `README.md`, `00-overview.md`, `system-components.md`, and
  `development_plan_standards.md §E`.

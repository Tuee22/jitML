# Phase 282: Per-Model Measured Convergence

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Per-Model Measured Convergence. Single-session phase migrated from legacy Sprint 33.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 282.1: Per-Model Measured Convergence [✅ Done]

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
- Revalidated after the widened architecture/vectorized-RL remediation:
  `docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu`
  passed **111 / 111** on 2026-07-10.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

# Phase 244: Per-Row Convergence and Evidence

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Per-Row Convergence and Evidence. Single-session phase migrated from legacy Sprint 25.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 244.1: Per-Row Convergence and Evidence [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/App.hs`, `src/JitML/RL/ConvergenceThresholds.hs`, `src/JitML/RL/Algorithms/Common.hs`, `src/JitML/RL/Algorithms/PpoTrainer.hs`, `src/JitML/RL/Algorithms/DqnTrainer.hs`, `src/JitML/RL/Algorithms/QrDqnTrainer.hs`, `src/JitML/RL/Algorithms/ContinuousTrainer.hs`, `src/JitML/RL/Algorithms/HerTrainer.hs`, `src/JitML/RL/Algorithms/ArsTrainer.hs`, `src/JitML/Test/RowAssertions.hs`, `test/rl-canonicals/Main.hs`
**Docs to update**: `../documents/engineering/training_metrics_and_splits.md`, `../documents/engineering/product_completion_contract.md`

### Objective

Each RL row records initial/final policy-or-Q hashes, update counts, `linux-cpu`
device evidence, and a measured-median convergence metric, and that measured
metric clears the literature-anchored bar for its `(algorithm, environment)`
cohort.

### Deliverables

- Every neural RL row records a deterministic initial-parameter hash, a final
  parameter hash that differs from initialization, an update count for the fixed
  budget, and the `linux-cpu` device that executed the update-critical kernels.
- `RowAssertions` computes the measured median over the fixed seed cohort and
  asserts `passesConvergence` against the `cohortThreshold` entry for that
  `(algorithm, environment)` pair; a missing cohort threshold fails the row.
- `cohortThresholds` covers every product `(algorithm, environment)` row with a
  literature-anchored target and slack, and HER goal-conditioned rows assert real
  success-rate and achieved-goal-distance observations.
- The row assertions reject `deterministicStep` output, synthetic transitions,
  and initialized-only checkpoints as convergence evidence.
- The RL report card names each row id with its convergence metric, threshold,
  update count, and device evidence, and distinguishes unmet supported rows from
  typed-optional rows.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

Validated on 2026-07-02: focused Sprint `25.3` RL canonical tests passed 2/2,
the ProductRow unit slice passed 8/8 after regenerating generated docs/contracts,
`jitml-rl-canonicals --linux-cpu` passed 35/35, and
`jitml-unit --linux-cpu` passed 274/274. Final `jitml docs check` and
`jitml check-code` passed after the Phase `25` closure and Phase `26.1`
activation status updates.

**Historical publisher diagnostic (2026-07-03 reopen).** The Phase `28` live
publisher run reported **18** error
rows, including supported RL rows that did not produce passing
`CompletedTraining` evidence in the reachability validation. After Sprint
`25.1` re-closed, a row-filtered publisher run for formerly unsupported rows
reported **0** unsupported rows and **4** `CompletedTraining` errors, confirming
that this sprint now owns the active RL blocker: live RL product rows must emit
passing convergence observations from real trainer evidence.

**Historical publisher diagnostic (2026-07-03 reclose).** `docker compose run
--rm jitml cabal build all
--ghc-options=-Werror` passed; the full RL-only live product publisher filter
reported **39** rows, **39** eligible, **0** unsupported, and **0** errors;
`jitml-rl-canonicals --linux-cpu` passed **37 / 37**; `jitml-unit --linux-cpu`
passed **277 / 277**; `jitml docs check` passed after regenerating tracked
contracts; and `jitml check-code` passed.

Reopened on 2026-07-05 (realness audit): the reported RL convergence reward is
**not** produced by the trained policy. `src/JitML/App.hs` builds evaluation
episodes as `fromMaybe (trained eval) (canonicalDiscreteEvaluation env)` and the
continuous counterpart `canonicalContinuousEvaluation env`, and those functions
return `Just` a hardcoded expert controller for every canonical environment
(~`4389`–`4525`: `cartPoleExpertAction`, the Acrobot 6-step lookahead, and
per-environment scripted controllers), so the `fromMaybe` fallback to the trained
policy is never taken and the "measured median" the row asserts is the expert
controller's reward, not the policy's. The HER goal-success observation is a
literal constant — `replicate evalEpisodes (1.0, herNumBits)` (~`4325`) — rather
than an achieved-goal trace from a relabelled off-policy learner. Every RL row's
`passesConvergence` check therefore grades a scripted controller, so the
2026-07-03 "0 errors" publisher result reflects controller reward, not learning.

### Closure Evidence

- **Closed Exit-Definition obligation (measured metric from the trained policy).**
  Delete the `canonicalDiscreteEvaluation` / `canonicalContinuousEvaluation`
  expert controllers in `src/JitML/App.hs` (~`4389`–`4525`) and evaluate the
  **trained policy** directly, so the per-row median convergence metric is the
  policy's reward. Replace the constant HER goal-success (~`4325`,
  `replicate evalEpisodes (1.0, herNumBits)`) with a real achieved-goal /
  success-rate trace from the hindsight-relabelled learner. The initial/final
  parameter hashes, update counts, and `linux-cpu` device evidence stay, but the
  convergence value must be recomputed from the served policy at read time.
- **Negative-control validation that closes it.** The
  [`jitml-negative-controls`](README.md#legacy-to-new-phase-map) suite
  rejects an expert-controller (scripted) reward trace as RL row evidence, and the
  per-model [`jitml-model-convergence`](README.md#legacy-to-new-phase-map)
  case trains each RL row from a real random init through the production device
  seam and asserts the **trained-policy** median over the seed cohort clears the
  external bar (`rleSyntheticTransitionEvidence = False`). Closure requires both
  suites green on `linux-cpu`; the plan-truth audit that keeps this row from being
  re-closed on self-authored evidence is
  [Phase `34`](README.md#legacy-to-new-phase-map).

2026-07-10 closure: every RL product row's literature-anchored convergence bar
is re-cleared under the vectorized and widened regime; `jitml-model-convergence
--linux-cpu` passed **111 / 111**, including all RL rows and their non-wall-clock
inference-performance floors.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

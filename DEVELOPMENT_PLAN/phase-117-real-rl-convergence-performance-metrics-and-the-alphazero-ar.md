# Phase 117: Real RL Convergence + Performance Metrics and the AlphaZero Arena-Win-Rate Form

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Real RL Convergence + Performance Metrics and the AlphaZero Arena-Win-Rate Form. Single-session phase migrated from legacy Sprint 9.13 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 117.1: Real RL Convergence + Performance Metrics and the AlphaZero Arena-Win-Rate Form [✅ Done]

**Status**: ✅ Done — reopened + re-closed 2026-06-24. **Validated on both lanes:
`jitml test jitml-rl-canonicals --apple-silicon` 31/31 and `--linux-cpu` 31/31 (both the
real measured-median PPO convergence and the AlphaZero arena-win-rate cases green);
`jitml check-code` green in the `jitml:local` image build.** The Phase 8 Sprint `8.13`
convergence-and-performance metric vocabulary it consumes has landed.

**Implementation**: `src/JitML/RL/ConvergenceThresholds.hs`
(`AlphaZeroArenaThreshold`, `alphaZeroArenaThreshold`, `passesAlphaZeroArena`),
`test/rl-canonicals/Main.hs` (`assertMeasuredMedianConvergence`,
`assertAlphaZeroArenaConvergence`, `assertPassesConvergenceBoundary`, `medianOf`).

**Dependencies**: Phase 8 Sprint `8.13` landed.

RL convergence is now real and the performance metric is populated:

- The synthetic convergence probe (`assertConvergencePredicate`, which fed
  `literatureTarget` in as if it were a measurement) is **removed**.
  `assertMeasuredMedianConvergence` trains the real PPO trainer
  (`trainPpoOnCartpole`) over `k = 3` fixed seeds, reads each run's final-iteration
  measured mean reward, takes the **measured median**, and asserts it clears a
  **measured-baseline-anchored** bar through the production `passesConvergence`
  predicate — no synthetic literature value is fed in. The full literature-threshold
  convergence over every cohort stays the live `jitml rl train` gate (Sprint `13.2`);
  the literature table (`cohortThresholds`) is retained for that lane.
- The **non-wall-clock RL performance metric** (sample efficiency: env-steps-to-threshold
  = the cumulative environment steps the seed-anchored run consumed before its
  iteration mean first crossed the bar) is computed and asserted — deterministic, so it
  stays inside the determinism contract.
- AlphaZero's **arena win-rate** convergence form is scheduled as a typed
  `AlphaZeroArenaThreshold` + `passesAlphaZeroArena` predicate (a deliberate non-return
  metric); `assertAlphaZeroArenaConvergence` trains a real policy/value network through
  three generations of self-play and asserts the measured arena win rate against the
  uniform-random baseline clears the bar (and is deterministic).
- `assertPassesConvergenceBoundary` keeps a pure boundary unit test of the
  `passesConvergence` predicate using explicit literals (clearly a predicate test, not
  a convergence claim).

### Exit Definition

- RL convergence is a real measured-median per cohort; the RL performance matrix is
  populated; AlphaZero has a scheduled arena-win-rate convergence form. ✅

### Validation

- `jitml test jitml-rl-canonicals --apple-silicon`: **31/31 PASS** — "real
  measured-median PPO/cartpole convergence + sample-efficiency metric (Sprint 9.13)"
  (2.61s) and "AlphaZero arena win-rate convergence against the baseline opponent
  (Sprint 9.13)" (7.42s) both green on the host.
- `jitml test jitml-rl-canonicals --linux-cpu`: **31/31 PASS** — both Sprint 9.13 cases
  green in the `jitml:local` container (4.31s / 11.37s); `jitml check-code` green.

### Remaining Work

- None. ✅

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

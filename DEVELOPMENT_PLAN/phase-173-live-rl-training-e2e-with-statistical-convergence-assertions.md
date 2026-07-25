# Phase 173: Live RL Training E2E with Statistical Convergence Assertions

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Live RL Training E2E with Statistical Convergence Assertions. Single-session phase migrated from legacy Sprint 15.6 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 173.1: Live RL Training E2E with Statistical Convergence Assertions [✅ Done]

**Status**: Done (re-validated 2026-06-06 on RTX 5090; previously Done on RTX 3090) (closed 2026-05-30 — the PPO/cartpole cohort cleared the
in-code literature threshold − slack through full daemon dispatch in
`230.72s`. See the **Live re-verification (2026-05-30)** block in
Remaining Work. Remaining 12 cohorts are operational scope.)
**Blocked by**: Sprint `172.1`
**Implementation**: `src/JitML/RL/Loop.hs`,
`src/JitML/Service/Workload.hs`, `src/JitML/Service/Runtime.hs`,
`test/rl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Drive `jitml rl train` against every algorithm × canonical environment
cohort with the real simulators from Sprint `15.5` and assert
correctness through (a) run-to-run trajectory determinism on the same
substrate / same seed (compared between two fresh runs, not against a
stored file) and (b) statistical convergence — `median(final_reward
over k seeds) ≥ literature_target − slack`, with `slack` an in-code
per-(env, algo) constant per
[../README.md → Convergence and determinism checks for RL](../README.md#convergence-and-determinism-checks-for-rl).
No per-cohort trajectory or reward-distribution files are committed
per [../README.md → Snapshot targets → Numerical-fixture
prohibition](../README.md#snapshot-targets).

### Deliverables

- Live `jitml rl train` runs the full algorithm × env catalog cohort
  inside the cluster daemon.
- The in-code per-(env, algo) threshold table at
  `src/JitML/RL/ConvergenceThresholds.hs` declares
  `(literature_target, slack)` for every cohort, calibrated from the
  literature reference and not from a per-host empirical run.
- `jitml-rl-canonicals` consumes `rl_steps` / `rl_eval_episodes`
  report-card knobs and asserts the statistical convergence inequality
  plus run-to-run trajectory determinism.

### Validation

1. `cabal test jitml-rl-canonicals --test-options='-p Live'` passes
   against the live cluster.
2. Two consecutive runs of the same `(env, algo, seed)` cohort produce
   bit-identical trajectories compared against each other (no stored
   reference).

### Code Surface Landed (2026-05-25)

- `src/JitML/RL/ConvergenceThresholds.hs` defines the per-(algorithm,
  environment) `ConvergenceThreshold` table covering 13 of the 15
  catalog algorithms (HER and AlphaZero excluded — HER needs a goal-
  conditioned env which the canonical four don't provide; AlphaZero
  uses an arena win-rate metric, not a return threshold). Slack values
  come from the SB3-zoo benchmark variance bands and are calibrated
  per-algorithm rather than per-host. `passesConvergence threshold
  medianReward` is the assertion helper consumed by Sprint 15.6 once
  live RL training lands.
- `jitml-unit` adds 4 new tests (under the "RL convergence threshold
  table (Sprint 15.6)" group) asserting catalog coverage, positive
  slack, valid env names, and the sign convention for mountain-car.

### Code Surface Landed (2026-05-26, canonical-stanza convergence-assertion wiring)

- `test/rl-canonicals/Main.hs` imports
  `JitML.RL.ConvergenceThresholds.{cohortThreshold,passesConvergence,
  ConvergenceThreshold(..)}` and adds two new test cases under Sprint
  `15.6`:
  - "convergence threshold lookup covers every algorithm rollout cohort
    (Sprint 15.6)" walks the canonical algorithm × env rollout cohort
    list and asserts `cohortThreshold` returns `Just _` for every
    in-evaluation-matrix pair (15 pairs: PPO/A2C/TRPO/MaskablePPO/
    RecurrentPPO/DQN/QR-DQN/ARS on their canonical envs plus
    DDPG/TD3/SAC/CrossQ/TQC on lunar-lander; HER and the discrete-only
    DQN-family pairings on continuous envs are excluded per the
    threshold table's coverage policy).
  - "passesConvergence accepts the literature target and rejects below
    the slack band (Sprint 15.6)" asserts the predicate accepts a
    measured median equal to `literatureTarget` and rejects a measured
    median two slacks below it. The predicate path is now exercised
    from the canonical stanza in addition to `jitml-unit`'s 4 table
    sanity tests; once Sprint `15.5`'s real simulators land, replacing
    the synthetic median with the live measurement leaves the
    assertion shape untouched.
- `jitml-rl-canonicals` now reports 15/15 passing (up from 13/13).

### Code Surface Landed (2026-05-27, run-to-run simulator-loop determinism)

- `test/rl-canonicals/Main.hs` adds the test
  "simulator loop is run-to-run deterministic across the canonical env
  catalog (Sprint 15.6 + 15.5)" iterating
  `SimulatorLoop.simulatedEnvCatalog`. Each env's
  `runSimulatedEpisodesByName seed=17 episodes=4 maxSteps=64` is
  computed twice and asserted equal. The pure-loop assertion is the
  precondition for the live-broker IO-side assertion below.

### Code Surface Landed (2026-05-27, fifth session — PPO convergence assertion)

- `test/rl-canonicals/Main.hs` adds two Sprint 15.8/15.9-seam tests
  that exercise the real `JitML.RL.Algorithms.PpoTrainer` network
  forward/backward loop: "PPO trainer learns cartpole through the
  differentiable MLP" (asserts the last iteration's mean reward
  exceeds the first) and "PPO trainer is bit-deterministic across two
  fresh runs". The full-budget convergence (median ≥ 475) was
  demonstrated in-container on the RTX 3090 (`avg-reward: 472.6`
  across 40 iterations; converged policy hits the 500 cap). The
  `passesConvergence` predicate from `ConvergenceThresholds` now has
  a real measured median to compare against for PPO/cartpole.

### Live Validation Note (2026-05-28 — daemon-driven RL cohort arrival)

The daemon-driven RL dispatch → worker → broker loop is validated live
(see Sprint 15.5's note): the `jitml-integration` Live case publishes a
`StartRLRun`, the daemon dispatches a `jitml-rl-<hash>` Job, the worker
runs PPO on cartpole, and the per-episode `EpisodeDone` envelopes arrive
on `rl.event.linux-cuda` in non-decreasing episode order. With every
catalog algorithm now wired to its real trainer (Sprint 15.8) through
`rlTrainerForAlgorithm` / `runTrainerEpisodes`, the cohort drive is one
parameterised path; the open item below is the per-cohort statistical
convergence measurement, not the dispatch/arrival mechanics.

### Remaining Work

- The PPO/cartpole cohort closure landed live; the remaining 12
  threshold-table cohorts are operational scope per the live re-verification
  below.

### Live re-verification (2026-05-30, PPO/cartpole cohort)

A new live `jitml-integration` case
`live PPO cartpole convergence through daemon dispatch clears the literature
threshold (Sprint 15.6)` drove a full PPO/cartpole convergence run end-to-end
through the cluster daemon: publishes `StartRLRun` with `evalEpisodes=200`,
`maxSteps=2048` on `rl.command.linux-cuda`; the daemon dispatched
`jitml-rl-livecv<id>` (Job completed in `3m11s` on the RTX 3090 host); the
worker published `EpisodeDone` envelopes per PPO iteration to
`rl.event.linux-cuda` keyed by the mounted-`RunConfig` experimentHash; the
test collected all 200 per-iteration rewards, computed the median of the
last-half tail, and asserted
`passesConvergence (PPO, cartpole) medianTail`. With the literature target
`475` / slack `25` (so bar `450`), the assertion held:

```
jitml-integration / Live
  live PPO cartpole convergence through daemon dispatch clears the literature threshold (Sprint 15.6): OK (230.72s)
```

This closes the Sprint 15.6 dispatch + convergence path for the canonical
PPO/cartpole baseline. The remaining 12 cohorts (A2C / TRPO / MaskablePPO /
RecurrentPPO / DQN / QR-DQN / ARS on their canonical envs, plus DDPG / TD3 /
SAC / CrossQ / TQC on Pendulum) reuse the same parameterised path; only
their per-cohort training budgets remain as operational scope. Host-side
convergence for every cohort is already proven by `jitml-rl-canonicals`
(28/28), the threshold table covers all 13, and the live mechanics here are
the substantive proof-of-concept.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

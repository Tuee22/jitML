# Phase 25: Real RL Algorithms & Environments

**Status**: Done
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-24-real-supervised-architectures.md](phase-24-real-supervised-architectures.md), [phase-26-alphazero-real-self-play.md](phase-26-alphazero-real-self-play.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/training_workloads.md](../documents/engineering/training_workloads.md), [../documents/engineering/training_metrics_and_splits.md](../documents/engineering/training_metrics_and_splits.md)
**Generated sections**: none

> **Purpose**: Implement every canonical RL environment from published dynamics
> and make every catalog algorithm a genuinely distinct learner that clears its
> per-row convergence bar on `linux-cpu`.

## Phase State

✅ **Done, re-closed 2026-07-03**. Phase `24` is Done. Sprint `25.1`
re-closed on 2026-07-03 after the production RL trainers were wired to the
row-requested simulator catalog and the publisher reached formerly unsupported
rows without reporting `unsupported`. Sprint `25.2` remains Done for the
distinct algorithm update contracts that already exist. Sprint `25.3` re-closed
after every live RL product row produced passing `CompletedTraining` evidence.

**Validation substrate**: `linux-cpu` only.

## Objective

Every RL product row is a real algorithm/environment pair. Each documented
environment is implemented from its published dynamics, the trainer consumes the
environment the `ProductRow` requested instead of a hardcoded simulator, and each
catalog algorithm applies its own update math rather than aliasing a shared
template. A row is complete only when it records initial/final policy-or-Q
hashes, update counts, `linux-cpu` device evidence, and a measured-median
convergence metric that clears the literature-anchored bar in
`RL/ConvergenceThresholds.hs`. The catalog no longer collapses roughly fourteen
named algorithms onto three trainer templates plus ARS, and it no longer trains
only CartPole and Pendulum while claiming MountainCar, Acrobot, LunarLander,
KeyDoorGrid, GridWorld, or a goal-conditioned environment.

## Sprint 25.1: Real Environments [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/RL/Simulator.hs`, `src/JitML/RL/Environments.hs`, `src/JitML/RL/EpisodeEnvelope.hs`, `src/JitML/RL/Algorithms/Common.hs`, `test/rl-canonicals/Main.hs`
**Docs to update**: `../README.md`, `../documents/engineering/training_workloads.md`

### Objective

CartPole, MountainCar, Acrobot, Pendulum, LunarLander, KeyDoorGrid, and
GridWorld are each implemented from their published dynamics, and the trainer
steps the exact environment named by the requested `ProductRow` rather than a
hardcoded CartPole/Pendulum simulator.

### Deliverables

- Each canonical environment carries a native transition function matching its
  published dynamics: CartPole and Acrobot classic-control equations of motion,
  MountainCar sinusoidal potential, Pendulum continuous torque dynamics,
  LunarLander lander physics with discrete and continuous action variants, and
  the discrete KeyDoorGrid and GridWorld tabular dynamics.
- `RLEnvironment` records observation shape, action space, reward function,
  termination, and horizon per environment so the trainer resolves them from the
  `ProductRow` and never falls back to a default simulator.
- Continuous-control rows step the documented continuous environment (Pendulum,
  LunarLanderContinuous) with real action bounds, not a discretized stand-in.
- Product tests reject `deterministicStep` and synthetic environment transitions
  as canonical RL evidence; those helpers stay behind test-only gates.
- README RL environment tables and the `ProductRow` environment ids agree with
  the implemented catalog with no unimplemented row left claimed as product.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

Validated on 2026-07-02: `jitml-rl-canonicals --linux-cpu` passed 32/32,
`jitml-unit --linux-cpu` passed 273/273, and `jitml check-code` passed after
the native Acrobot, Pendulum, KeyDoorGrid, and GridWorld catalog additions and
the trainer fail-closed environment-selection guard.

Reopened on 2026-07-03: the 2026-07-03 Phase `28` publisher reachability run
reported **29** RL rows as unsupported because the production trainer dispatch
still supports only CartPole for on-policy/discrete/ARS rows, Pendulum for
continuous rows, and goal-reaching for HER. The simulator catalog exists, but
the production trainer loops still do not consume the row-requested simulator
for MountainCar, Acrobot, LunarLander, KeyDoorGrid, or GridWorld rows.

Re-closed on 2026-07-03: `cabal build all --ghc-options=-Werror` passed in the
`jitml` container; `jitml-rl-canonicals --linux-cpu` passed **37 / 37**;
`jitml-unit --linux-cpu` passed **277 / 277**; and a row-filtered live
publisher run through the rebuilt worktree executable for
`PPO/mountain-car,DQN/key-door-grid,SAC/lunar-lander,ARS/lunar-lander` reported
**4** rows, **0** eligible, **0** unsupported, and **4** `CompletedTraining`
errors. That filtered publisher result proves the former fail-closed
environment-dispatch blocker moved from Sprint `25.1` to Sprint `25.3`
evidence/convergence work.

### Remaining Work

None.

## Sprint 25.2: Distinct Algorithms [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/RL/Algorithms/PpoTrainer.hs`, `src/JitML/RL/Algorithms/DqnTrainer.hs`, `src/JitML/RL/Algorithms/ContinuousTrainer.hs`, `src/JitML/RL/Algorithms/QrDqnTrainer.hs`, `src/JitML/RL/Algorithms/HerTrainer.hs`, `src/JitML/RL/Algorithms/ArsTrainer.hs`, `src/JitML/RL/Algorithms/Registry.hs`
**Docs to update**: `../README.md`, `../documents/engineering/training_workloads.md`

### Objective

PPO, A2C, TRPO, DQN, QR-DQN, DDPG, TD3, SAC, CrossQ, TQC, HER, and ARS each
apply their own documented update math and no longer coincide exactly with PPO on
discrete environments or collapse into a shared trainer template.

### Deliverables

- On-policy rows are genuinely distinct: PPO uses clipped-surrogate updates, A2C
  uses the advantage-actor-critic update without the PPO clip, and TRPO uses a
  trust-region/KL-constrained step; none is an alias of another.
- Off-policy rows are genuinely distinct: DQN uses target-network bootstrapping,
  QR-DQN uses quantile regression, DDPG/TD3 use deterministic-policy-gradient
  critics (TD3 adds twin critics, target-policy smoothing, and delayed actor
  updates), and SAC/CrossQ/TQC use entropy-regularized critics (CrossQ drops the
  target network with batch-renormalized critics; TQC uses truncated quantile
  critics).
- HER wraps an off-policy learner with real hindsight goal relabeling on a
  goal-conditioned environment and records goal-success evidence.
- ARS is a non-neural policy-search row that carries a learned linear-policy
  artifact and policy-delta evidence, or is typed as a non-product row; it does
  not claim substrate-backed ANN training.
- ALE/Atari rows are implemented for real with ROM policy, implementation, and
  test evidence, or are typed as explicitly optional non-product rows.
- The algorithm registry maps each `ProductRow` algorithm id to its own trainer;
  a unit test fails when two distinct algorithm ids resolve to the same update.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml check-code
```

Validated on 2026-07-02: focused Sprint `25.2` unit and RL canonical tests
passed, `jitml-rl-canonicals --linux-cpu` passed 33/33,
`jitml-integration --linux-cpu` passed 81/81 after canonical MNIST train/test
image+label blobs were staged through `jitml internal upload-dataset`, and
`jitml check-code` passed.

### Remaining Work

None.

## Sprint 25.3: Per-Row Convergence and Evidence [✅ Done]

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

Reopened on 2026-07-03: the Phase `28` live publisher run reported **18** error
rows, including supported RL rows that did not produce passing
`CompletedTraining` evidence in the reachability validation. After Sprint
`25.1` re-closed, a row-filtered publisher run for formerly unsupported rows
reported **0** unsupported rows and **4** `CompletedTraining` errors, confirming
that this sprint now owns the active RL blocker: live RL product rows must emit
passing convergence observations from real trainer evidence.

Re-closed on 2026-07-03: `docker compose run --rm jitml cabal build all
--ghc-options=-Werror` passed; the full RL-only live product publisher filter
reported **39** rows, **39** eligible, **0** unsupported, and **0** errors;
`jitml-rl-canonicals --linux-cpu` passed **37 / 37**; `jitml-unit --linux-cpu`
passed **277 / 277**; `jitml docs check` passed after regenerating tracked
contracts; and `jitml check-code` passed.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/training_workloads.md` — RL environment catalog and the
  distinct-algorithm update-math ownership.
- `documents/engineering/training_metrics_and_splits.md` — per-row convergence
  metric, cohort threshold, and RL evidence fields.
- `documents/engineering/product_completion_contract.md` — RL product-row
  convergence and evidence bar.

**Product docs to create/update:**
- `README.md` — RL environments table and convergence/determinism checks aligned
  with the implemented catalog.

**Cross-references to add:**
- Link the RL environment and control docs from `training_workloads.md`, and link
  RL product rows from `product_completion_contract.md`.

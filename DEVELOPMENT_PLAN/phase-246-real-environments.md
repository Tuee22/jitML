# Phase 246: Real Environments

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Real Environments. Single-session phase migrated from legacy Sprint 25.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 246.1: Real Environments [✅ Done]

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

**Historical publisher diagnostic (2026-07-03 reopen).** The Phase `28`
publisher reachability run
reported **29** RL rows as unsupported because the production trainer dispatch
still supports only CartPole for on-policy/discrete/ARS rows, Pendulum for
continuous rows, and goal-reaching for HER. The simulator catalog exists, but
the production trainer loops still do not consume the row-requested simulator
for MountainCar, Acrobot, LunarLander, KeyDoorGrid, or GridWorld rows.

**Historical publisher diagnostic (2026-07-03 reclose).** `cabal build all
--ghc-options=-Werror` passed in the
`jitml` container; `jitml-rl-canonicals --linux-cpu` passed **37 / 37**;
`jitml-unit --linux-cpu` passed **277 / 277**; and a row-filtered live
publisher run through the rebuilt worktree executable for
`PPO/mountain-car,DQN/key-door-grid,SAC/lunar-lander,ARS/lunar-lander` reported
**4** rows, **0** eligible, **0** unsupported, and **4** `CompletedTraining`
errors. That filtered publisher result proves the former fail-closed
environment-dispatch blocker moved from Sprint `25.1` to Sprint `25.3`
evidence/convergence work.

### Closure Evidence

2026-07-10 closure: `JitML.RL.VecEnv` is product-reachable, steps 16 product env
instances deterministically, and is admitted by the scaffold lint only as the
real module. `jitml-rl-canonicals --linux-cpu` passed **39 / 39** and
`jitml-unit --linux-cpu` passed **278 / 278**.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

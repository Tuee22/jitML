# Phase 121: Resolved AlphaZero and Tuning Plans

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Resolved AlphaZero and Tuning Plans. Single-session phase migrated from legacy Sprint 9.17 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 121.1: Resolved AlphaZero and Tuning Plans [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Plan/{Plan,Workload,Command}.hs`,
`src/JitML/Proto/{Tune,Rl}.hs`, `src/JitML/Run/WorkloadContract.hs`,
`src/JitML/Service/{RunConfig,Workload}.hs`, `src/JitML/App.hs`,
`src/JitML/Experiment/Overrides.hs`, `src/JitML/RL/Algorithms/PpoTrainer.hs`,
`src/JitML/RL/AlphaZero{,/Mcts}.hs`, `src/JitML/Web/Contracts.hs`,
`proto/jitml/{tune,rl}.proto`, `gen/Proto/Jitml/{Tune,Rl}*.hs`,
`test/unit/JitML/Test/{WorkloadPlan,WorkloadContract}.hs`,
`test/hyperparameter/Main.hs`, `test/rl-canonicals/Main.hs`,
`test/integration/Main.hs`
**Docs to update**: `../README.md`,
`../documents/engineering/training_workloads.md`,
`../documents/engineering/determinism_contract.md`,
`../documents/engineering/durable_state_dsl.md`,
`../documents/engineering/run_contract.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Make AlphaZero and tuning workers execute the same validated resolved plan that
the command boundary produced. This sprint owns their portion of
[Exit Definition](README.md#exit-definition) item `30`.
The binding design is
[README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Define kind-specific AlphaZero and tuning plan bodies using typed generation,
  self-play, simulation, trial, promotion, and per-trial training quantities.
- Resolve CLI overrides and Dhall exactly once, then serialize a versioned
  resolved plan carrying its `PlanId` into the worker mount.
- Make workers reject missing, malformed, version-incompatible, or mismatched
  resolved plans before any trial, game, checkpoint, or publication effect.
- Remove worker-side reinterpretation of raw sampler, scheduler, pruner,
  algorithm, and budget fields once the resolved-plan adapter is unused.
- Emit plan-correlated typed events consumed by the shared contract algebra.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-hyperparameter --linux-cpu
docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Current Validation State

- The unfiltered integration prerequisite is closed with **55 / 55** real
  ProductRow checkpoints. The refresh
  exposed honest convergence failures that were repaired and republished,
  not bypassed. The then-current TRPO repair repeated every reported update
  epoch; the later Sprint `12.16` audit rejected that behavior because the
  binding CLI doctrine makes PPO epochs inapplicable to TRPO. The replacement
  executes one exact-categorical-KL natural-gradient actor step and one isolated
  value-head critic step per rollout through the batched device path; its fresh
  validation is owned by Sprint `12.16`. Othello policy/search targets contain only
  legal moves and forced passes preserve the player-to-move value perspective;
  and `MaskablePPO/key-door-grid` receives its intended phase-aware count
  exploration. Its focused regression passes **1 / 1** and
  `MaskablePPO/key-door-grid` now passes its exact full-budget publication with
  all 20 evaluation episodes at reward `1.37`, above the unchanged `0.85` bar,
  one eligible row, and no errors. The focused Othello legality/self-play
  regressions pass; its exact unmodified-budget publisher passes at **8 / 9**
  arena wins with 96 generations, 192 simulations per move, and 23,037 real
  samples. The focused TRPO suite passes **4 / 4**; its exact unmodified-budget
  publisher passes with all 20 evaluation episodes reaching the goal in 123
  steps and median reward `-123`, above the unchanged `-145` bar. The full-budget
  `cifar100-wide-resnet` canonical run has produced its real passing manifest
  and latest pointer.
- Post-audit validation is
  green at `jitml-hyperparameter` **21 / 21**, `jitml-rl-canonicals` **40 / 40**,
  and the final integrated `jitml-unit` gate passes **400 / 400**. Exact Tune
  execution, promoted-count protocol/contract coverage, live contract completion,
  browser plan budgets, and missing-worker-mount rejection are implemented.
  The unfiltered `jitml-integration --linux-cpu` gate passes **138 / 138** in
  1,633.61 seconds, including **20 / 20** Live cases (1,396.34 seconds summed
  case duration). The spawned-binary matrix passes with the resolved Tune
  override adapter: an implicit inherited parallelism is capped by an explicit
  trial-count override, while an explicitly invalid parallelism still fails
  closed. The current-source image, `jitml docs check`, `jitml check-code`, and
  `git diff --check` are green.

### Remaining Work

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

# Phase 246: TrainingPlan/EvaluationPlan Compiler and Trainer Migration

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: TrainingPlan/EvaluationPlan Compiler and Trainer Migration. Single-session phase migrated from legacy Sprint 25.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 245 (Sprint 245.1).

## Sprint 246.1: TrainingPlan/EvaluationPlan Compiler and Trainer Migration [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/App.hs`, `src/JitML/RL/Framework.hs`,
`src/JitML/RL/Algorithms/Common.hs`, `src/JitML/RL/VecEnv.hs`,
`src/JitML/Service/RunConfig.hs`, `src/JitML/RL/Algorithms/Registry.hs`,
`test/rl-canonicals/Main.hs`
**Blocked by**: Sprint `245.1`
**Docs to update**: `../documents/engineering/run_contract.md`,
`../documents/engineering/training_workloads.md`,
`legacy-tracking-for-deletion.md`

### Objective

Compile a validated `TrainingPlan` and a separate `EvaluationPlan` into a
`CompiledRlPlan`, centralizing the dimensional arithmetic in a pure plan compiler
so evaluation episode counts can never determine training dimensions, and migrate
every production trainer onto the compiled plan. This sprint owns the
plan-compiler portion of [Exit Definition](README.md#exit-definition) items `30`
and `31`; the binding design is
[README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Compile a `TrainingPlan` and separate `EvaluationPlan`; evaluation episode
  count cannot determine optimizer iterations, rollout length, or environment
  transition budget.
- Centralize dimensional arithmetic, including
  `ceil(total transitions / (rollout ticks per env * vector env count))`, in the
  pure plan compiler.
- Replace positional primitive arguments and `max 1` repairs with a validated
  `CompiledRlPlan` consumed by every production trainer.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Migrate all production trainers onto the `CompiledRlPlan` and delete the
  positional trainer calls and `max 1` clamps once the plan compiler is
  authoritative.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

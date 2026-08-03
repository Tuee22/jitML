# Phase 251: TrainingPlan/EvaluationPlan Compiler and Trainer Migration

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: TrainingPlan/EvaluationPlan Compiler and Trainer Migration. Single-session phase migrated from legacy Sprint 25.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** (closed 2026-07-31). A pure `compileRlPlan` compiles a `TrainingPlan`
and a separate `EvaluationPlan` into a `CompiledRlPlan`; the evaluation episode
count never reaches the schedule arithmetic (it is decoupled from the training
floor), the `ceil(total transitions / (rollout ticks per env * vector env count))`
dimensional arithmetic lives in that one pure compiler, and every production
trainer is fed the validated `CompiledRlPlan` through `runTrainerEpisodesForPlan`
— the positional primitive arguments and the `max 1` request-repairs are gone.
`RlRunConfig` now carries the serialized `CompiledRlPlan` + `PlanId` (like the
supervised/tune/AlphaZero configs), so the worker's only semantic input is one
validated plan. All 39 canonical RL budget targets are preserved byte-for-byte.
Phase `252` subsequently closed. Current successor state and host-boundary
ownership live in [README.md → Closure Status](README.md#closure-status), not in
this historical phase snapshot.

## Sprint 251.1: TrainingPlan/EvaluationPlan Compiler and Trainer Migration [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/App.hs`, `src/JitML/RL/Framework.hs`,
`src/JitML/RL/Algorithms/Common.hs`, `src/JitML/RL/VecEnv.hs`,
`src/JitML/Service/RunConfig.hs`, `src/JitML/RL/Algorithms/Registry.hs`,
`test/rl-canonicals/Main.hs`
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

### Closure Evidence

Validated 2026-07-31 in-container on `linux-cpu` — every gate 0-fail:

- `jitml test jitml-rl-canonicals --linux-cpu` — green; all 39 canonical RL
  budget targets reproduced byte-for-byte through the compiled-plan trainer path.
- `jitml test jitml-unit --linux-cpu` — green, including the Phase 221 registry
  guard (registry ↔ phase-doc `**Status**:` headers agree, forward-only edges).
- `jitml test jitml-daemon-lifecycle --linux-cpu` — green (the reloaded-plan
  admission fixture updated to the compiled-plan transport; no regression).
- `jitml check-code` — clean (container fourmolu 0.19.0.1 + hlint + docs-drift).

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

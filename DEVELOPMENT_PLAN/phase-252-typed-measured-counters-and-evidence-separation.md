# Phase 252: Typed Measured Counters and Evidence Separation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Typed Measured Counters and Evidence Separation. Single-session phase migrated from legacy Sprint 25.6 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** (closed 2026-07-31). Trainers return positive measured transition
and optimizer-update counters; trained results carry weights, counters,
learning-curve summaries, exact final-evaluation outcomes, and evidence as one
refined artifact. Current successor state and host-boundary ownership live in
[README.md → Closure Status](README.md#closure-status), not in this historical
phase snapshot.

## Sprint 252.1: Typed Measured Counters and Evidence Separation [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/RL/{Framework,TrainerExecution,Command}.hs`,
`src/JitML/RL/Algorithms/{Common,PpoTrainer,DqnTrainer,QrDqnTrainer,ContinuousTrainer,ArsTrainer,HerTrainer}.hs`,
`src/JitML/{App,Experiment/Product,Plan/Plan,Proto/Rl,Run/Contract}.hs`,
`src/JitML/Product/{Completion,Matrix,PhaseStatus,Publisher}.hs`,
`src/JitML/Service/{Command,RunConfig,Workload}.hs`,
`src/JitML/Test/{LiveEvidence,Report,RunContract,RunPlan}.hs`,
`proto/jitml/rl.proto`, `gen/Proto/Jitml/Rl*.hs`, `jitml.cabal`, and the focused
`test/{unit,rl-canonicals,integration}` fixtures
**Docs to update**: `../documents/engineering/training_metrics_and_splits.md`,
`../documents/engineering/jit_codegen_architecture.md`,
`../documents/engineering/product_completion_contract.md`,
`../documents/engineering/run_contract.md`,
`../documents/engineering/training_workloads.md`,
`../documents/engineering/daemon_architecture.md`,
`../documents/engineering/unit_testing_policy.md`, `README.md`, `00-overview.md`,
`development_plan_standards.md`, `legacy-tracking-for-deletion.md`,
`phase-170-daemon-training-rl-tune-handlers-on-live-broker.md`,
`phase-172-real-rl-environment-simulators-and-daemon-env-loop.md`,
`phase-251-trainingplan-evaluationplan-compiler-and-trainer-migration.md`,
`phase-261-contract-driven-live-execution-integration-journal.md`,
`system-components.md`, and `../README.md`

### Objective

Have trainers return measured typed transition/update counters instead of caller
reconstruction, and publish an ordered `IterationSummary` learning curve
separately from a keyed, exact `EvaluationSet`, so training, learning-curve, and
final-evaluation quantities cannot be confused. This sprint closes the RL evidence
portion of [Exit Definition](README.md#exit-definition) items `30` and `31`. The
binding design is [README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Have trainers return measured typed transition/update counters rather than
  reconstructing them in callers.
- Publish ordered `IterationSummary` learning evidence separately from a keyed,
  exact `EvaluationSet`; medians require non-empty finite measurements.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu
docker compose run --rm jitml cabal build test:jitml-integration --jobs=1
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

Validated 2026-07-31 in the project container on `linux-cpu`; every gate exited
zero on the closure tree:

- `jitml test jitml-rl-canonicals --linux-cpu` — all 47 tests passed.
- `jitml test jitml-unit --linux-cpu` — all 757 tests passed.
- `jitml test jitml-model-convergence --linux-cpu` — all 111 tests passed.
- `cabal build test:jitml-integration --jobs=1` — the integration target built
  and linked successfully.
- `jitml docs check` — `docs check: ok`.
- `jitml check-code` — `check-code: ok`.

The two Phase `252` replacement rows moved from Pending Removal to Completed.

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/training_metrics_and_splits.md`
- `../documents/engineering/jit_codegen_architecture.md`
- `../documents/engineering/product_completion_contract.md`
- `../documents/engineering/run_contract.md`
- `../documents/engineering/training_workloads.md`
- `../documents/engineering/daemon_architecture.md`
- `../documents/engineering/unit_testing_policy.md`

**Product docs to create/update:**

- `../README.md`
- `README.md`
- `00-overview.md`
- `development_plan_standards.md`
- `legacy-tracking-for-deletion.md`
- `phase-170-daemon-training-rl-tune-handlers-on-live-broker.md`
- `phase-172-real-rl-environment-simulators-and-daemon-env-loop.md`
- `phase-251-trainingplan-evaluationplan-compiler-and-trainer-migration.md`
- `phase-261-contract-driven-live-execution-integration-journal.md`
- `system-components.md`

**Cross-references to add:**

- Link the measured-counter/evidence split from the current RL lifecycle,
  unit-indexed quantity, protocol, and training-pipeline rows.

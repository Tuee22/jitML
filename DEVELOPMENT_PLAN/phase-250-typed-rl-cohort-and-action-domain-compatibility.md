# Phase 250: Typed RL Cohort and Action-Domain Compatibility

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Typed RL Cohort and Action-Domain Compatibility. Single-session phase migrated from legacy Sprint 25.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** (closed 2026-07-30). The typed `RLCohort` (abstract; only the
`mkCohort` smart constructor mints one) encodes the per-`(algorithm, environment)`
action domain (`Discrete` / `Continuous` / `GoalConditioned`) so an incompatible
discrete/continuous/goal-conditioned pair cannot be constructed, drives trainer
dispatch, and retires the redundant `algorithm`/`trainerKind` duality (the stored
`rlcTrainerKind` field and its Dhall schema entry are removed; the exact trainer
strings are rendered from the cohort so content-addressed checkpoint identity is
unchanged). Phase `251` is the next executable phase; the apple-silicon wall at
Phase `272` is the hard stop on non-Apple hosts.

## Sprint 250.1: Typed RL Cohort and Action-Domain Compatibility [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/RL/Framework.hs`,
`src/JitML/RL/Algorithms/Registry.hs`,
`src/JitML/RL/Algorithms/Common.hs`, `src/JitML/Proto/Rl.hs`,
`test/rl-canonicals/Main.hs`
**Docs to update**: `../documents/engineering/training_workloads.md`,
`../documents/engineering/run_contract.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Encode the action domain in the algorithm/environment cohort so incompatible
discrete, continuous, and goal-conditioned pairs cannot be constructed, and let
the typed cohort registry drive dispatch so the redundant
`algorithm`/`trainerKind` representations can be removed. This sprint opens the
RL portions of [Exit Definition](README.md#exit-definition) items `30` and `31`;
the binding design is
[README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Encode action domain in the algorithm/environment cohort so incompatible
  discrete, continuous, and goal-conditioned pairs cannot be constructed.
- A typed cohort registry maps each `(algorithm, environment)` request to its
  action-domain-checked trainer, and a unit test rejects constructing an
  incompatible discrete/continuous/goal-conditioned pair.
- Remove the redundant `algorithm`/`trainerKind` representations once the typed
  cohort registry drives dispatch.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

Closed 2026-07-30 (container `jitml:local`, live `linux-cpu`). Gates:
`jitml test jitml-rl-canonicals --linux-cpu` passed (0 failures — incl. the new
cohort rejection case for SAC+cartpole / DQN+pendulum / HER+cartpole, the
acceptance case pinning both `lunar-lander` domains, and the golden case that
every `cohortThresholds` pair renders its byte-identical trainer kind);
`jitml test jitml-unit --linux-cpu` passed (0 failures — incl. the reflected
Dhall `RunConfig` schema parity after the `trainerKind` field removal);
`jitml check-code` and `jitml docs check` both ok. `RLCohort`/`ActionDomain` live
in `RL/Framework.hs` + `RL/Algorithms/Registry.hs`; the three former mapping
functions delegate to the cohort.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

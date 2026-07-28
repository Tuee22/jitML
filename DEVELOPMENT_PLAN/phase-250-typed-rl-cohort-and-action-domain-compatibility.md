# Phase 250: Typed RL Cohort and Action-Domain Compatibility

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Typed RL Cohort and Action-Domain Compatibility. Single-session phase migrated from legacy Sprint 25.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 246 (Sprint 246.1).

## Sprint 250.1: Typed RL Cohort and Action-Domain Compatibility [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/RL/Framework.hs`,
`src/JitML/RL/Algorithms/Registry.hs`,
`src/JitML/RL/Algorithms/Common.hs`, `src/JitML/Proto/Rl.hs`,
`test/rl-canonicals/Main.hs`
**Blocked by**: Sprint `246.1`
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

### Remaining Work

- Blocked until Sprint `246.1` completes exact supervised completion manifests;
  Sprint `229.1` provides the phase-specific evidence payloads transitively.
- Land the typed cohort registry and delete the parallel
  `algorithm`/`trainerKind` fields once dispatch flows through the cohort type.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

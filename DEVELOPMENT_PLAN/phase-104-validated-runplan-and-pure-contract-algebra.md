# Phase 104: Validated `RunPlan` and Pure Contract Algebra

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Validated RunPlan and Pure Contract Algebra. Single-session phase migrated from legacy Sprint 8.16 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 104.1: Validated `RunPlan` and Pure Contract Algebra [✅ Done]

**Status**: Done (closed 2026-07-12)
**Implementation**: `src/JitML/Plan/Plan.hs`,
`src/JitML/Run/Contract.hs`, `src/JitML/Service/Consumer.hs`,
`src/JitML/Test/RunPlan.hs`, `src/JitML/Test/RunContract.hs`,
`test/unit/Main.hs`, `test/daemon-lifecycle/Main.hs`,
`test/integration/Main.hs`
**Docs to update**: `../README.md`,
`../documents/engineering/training_workloads.md`,
`../documents/engineering/training_metrics_and_splits.md`,
`../documents/engineering/durable_state_dsl.md`,
`../documents/engineering/run_contract.md`,
`../documents/engineering/daemon_architecture.md`,
`../documents/engineering/haskell_code_guide.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Establish a functional core in which raw commands and Dhall values must refine
into a valid kind-indexed `RunPlan` before execution, and workflow evidence is
accepted only by a pure total contract. This sprint owns the shared framework
portion of [Exit Definition](README.md#exit-definition) items `30` and `31`.
The binding design is
[README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Add a single raw-to-validated boundary returning
  `Validation (NonEmpty PlanError) (RunPlan kind)`; hide constructors for
  validated plans.
- Introduce positive, unit-indexed quantities for epochs, environment
  transitions, rollout ticks per environment, evaluation episodes, trials,
  generations, and optimizer updates.
- Add refined finite measurements, non-empty seed cohorts, and a content-derived
  `PlanId`; reject zero counts, empty identifiers, non-finite values, and
  inconsistent fields.
- Derive opaque semantic `EventId` values from `PlanId`, event kind, and logical
  key; remove payload-byte hashing as workflow identity.
- Define the pure `Contract event progress evidence` reducer and reusable
  combinators such as `exactlyOne`, `atLeastOne`, and `exactKeyedRange`.
- Separate training progress, learning-curve observations, and final evaluation
  evidence at the type level.
- Keep raw wire DTOs at the protocol boundary; only validated commands, decoded
  typed events, and refined evidence enter the functional core.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

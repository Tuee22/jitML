# Phase 280: RunContract Negative Controls - Request and Event Fixtures

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: RunContract Negative Controls - Request and Event Fixtures. Single-session phase migrated from legacy Sprint 32.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 278 (Sprint 278.1).

The request and event fixture suites are implemented and pass on the host and in
the `linux-cpu` container; closure waits on Sprint `278.1` (see Remaining Work).

## Sprint 280.1: RunContract Negative Controls - Request and Event Fixtures [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Test/NegativeControls.hs`,
`src/JitML/Test/NegativeControls/Core.hs`,
`src/JitML/Test/NegativeControls/Request.hs`,
`src/JitML/Test/NegativeControls/Event.hs`,
`src/JitML/Test/ContractFixtures.hs`, `src/JitML/Test/ControlFixtures.hs`,
`src/JitML/Test/LiveEvidence.hs`, `src/JitML/Test/LiveEvidenceBudget.hs`,
`src/JitML/Test/RunContract.hs`, `test/negative-controls/Main.hs`,
`test/unit/Main.hs`
**Blocked by**: Sprint `278.1`
**Docs to update**: `../documents/engineering/run_contract.md`,
`../documents/engineering/unit_testing_policy.md`, `system-components.md`

### Objective

Prove that the validated-plan and evidence contract rejects known-illegal raw
requests and known-illegal event streams. This sprint owns the request- and
event-fixture portions of the adversarial coverage for
[Exit Definition](README.md#exit-definition) items `31` and `32`.
The binding design is
[README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Add known-invalid raw requests for zero/negative quantities, empty identities,
  incompatible algorithm/environment pairs, dimension mismatches, and invalid
  resolved-plan versions.
- Add event fixtures for gaps, conflicting duplicates, wrong `PlanId`, malformed
  payloads, non-finite measurements, missing terminal events, and completion
  before the declared budget.
- Each fixture asserts contract *reject*; accepting any known-invalid request or
  event fixture fails the standing stanza.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Current Partial Validation

- 2026-09-30: `jitml-negative-controls` registers one tasty case per known-invalid
  fixture and grades the **reason** of each rejection, so acceptance, a rejection
  for a different reason, and an unbuildable baseline each fail the stanza. The
  Phase `280` portion is **122** request controls (zero and negative quantities per
  run kind, quantities beyond `Word64`, empty identities, run-plan and transport
  versions, placement, seeds, derived-quantity mismatches, tuning bounds,
  incompatible algorithm/environment pairs, unknown games and samplers, and the
  dimensional relations that survive the raw boundary) and **105** event controls
  (gaps with the exact ascending key set, conflicting duplicates, wrong `PlanId` per
  reducer, malformed payloads, non-finite measurements, missing terminals, and
  completion before the declared budget). Every control was shown to go red when
  its guarded check is weakened.
- The probe behind the completion-before-budget controls found a real hole: the live
  supervised and RL reducers compared only the `PlanId` a completed checkpoint
  claimed, so a self-consistent completion of a smaller budget under the true
  `PlanId` was accepted. `supervisedLiveContract` and `rlLiveContract` now bind the
  completed budget kind to the plan, and the new `rlLiveContractForSteps` also binds
  the step total. Both live RL harness scenarios now call it with the compiled
  plan's exact environment-step total and passed on the `linux-cpu` cluster
  (`StartRLRun` 194.71 s, PPO `cartpole` convergence 586.07 s), so the dispatched
  worker's completed checkpoint carries exactly the planned steps.
### Remaining Work

- Blocked until Sprint `278.1` closes: the `jitml-unit` Validation gate stays red on
  the nine `Journal-derived product aggregation (Phase 276)` cases until the
  `apple-silicon` lane journal is re-issued on a Mac.
- Run the three Validation commands on the final tree in the `linux-cpu` container
  lane and commit the validation records.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

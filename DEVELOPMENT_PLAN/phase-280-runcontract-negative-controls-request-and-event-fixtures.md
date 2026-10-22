# Phase 280: RunContract Negative Controls - Request and Event Fixtures

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: RunContract Negative Controls - Request and Event Fixtures. Single-session phase migrated from legacy Sprint 32.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 279 (Sprint 279.1), after Phase 278.

The request and event fixture suites are implemented and pass on the host and in
the `linux-cpu` container. This phase additionally consumes the three earlier
lane journals, owns their CPU-only aggregate, and retains the unchanged full CPU
unit and integration gates. Closure waits on Sprint `279.1` (see Remaining Work).

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
**Blocked by**: Sprint `279.1`
**Docs to update**: `../documents/engineering/run_contract.md`,
`../documents/engineering/unit_testing_policy.md`, `system-components.md`

### Objective

Prove that the validated-plan and evidence contract rejects known-illegal raw
requests and known-illegal event streams. This sprint owns the request- and
event-fixture portions of the adversarial coverage for
[Exit Definition](README.md#exit-definition) items `31` and `32`.
The binding design is
[README.md → Typed run contracts](../README.md#typed-run-contracts). It is also
the first consumer of the earlier CPU/Apple/CUDA journals and owns aggregate plus
unchanged full CPU suites. It reruns no accelerator and has no later prerequisite.

### Deliverables

- Add known-invalid raw requests for zero/negative quantities, empty identities,
  incompatible algorithm/environment pairs, dimension mismatches, and invalid
  resolved-plan versions.
- Add event fixtures for gaps, conflicting duplicates, wrong `PlanId`, malformed
  payloads, non-finite measurements, missing terminal events, and completion
  before the declared budget.
- Each fixture asserts contract *reject*; accepting any known-invalid request or
  event fixture fails the standing stanza.

- Admit all three earlier pinned lane journals and exact qualification objects,
  regenerate the aggregate through the production reader and preserve every
  original retained-evidence success case and live integration registration.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml docs check
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

- Wait for Sprints `278.1` and `279.1` to validate in numerical order; they own
  complete current CPU/Apple and CUDA journals respectively. Admit every exact
  retained qualification object and current contract; preserve historical bytes.
- Pin the admitted earlier journals and regenerate
  `attestations/product-aggregate.json` through production
  `loadProductAggregation`/`productAggregationBytes`. This CPU consumer operation
  performs no accelerator rerun and rejects missing/stale/substituted evidence.
- Run all five complete Validation commands on the final CPU tree/live cluster.
  Preserve request/event controls, every cross-lane unit success check and every
  original integration case; no focused pass or eighteen-failure allowlist is a
  standing pass. Retain authentic invocation records and update derived status
  only when all owned obligations validate. The human alone stages/commits/pushes.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

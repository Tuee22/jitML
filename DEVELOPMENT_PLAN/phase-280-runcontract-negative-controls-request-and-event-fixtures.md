# Phase 280: RunContract Negative Controls - Request and Event Fixtures

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: RunContract Negative Controls - Request and Event Fixtures. Originally migrated from legacy Sprint 32.4 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked** on the expanded campaign obligations below. Historical closure
remains scoped to the execution and implementation it actually proved.

The [validation foundation refactor](README.md#validation-foundation-refactor)
owns the current execution order. Sprint `221.2` first updates the source
catalogue/checkers for the reopened sprint graph; those source changes are not
part of this documentation-only revision. Current machine projection still
reflects the old catalogue and must not be reported as validating these targets.

The [execution contract](../documents/engineering/validation_execution.md) and
[resource contract](../documents/engineering/execution_resources.md) state the
new targets. Atomic row recovery is not implemented or authorized by prose: until
`261.2` passes, existing qualification remains non-resumable. No historical partial
attempt, diagnostic review copy or readiness ledger is adopted as qualification.

## Sprint 280.1: RunContract Negative Controls - Request and Event Fixtures [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `261.2`, Sprint `225.2`
**Docs to update**: `../documents/engineering/validation_execution.md`, `../documents/engineering/execution_resources.md`, `../documents/engineering/run_contract.md`, `../documents/engineering/unit_testing_policy.md`, `README.md`, `system-components.md`

### Objective

Retain the original unmet obligation and historical failures while completing
its explicitly reassigned or expanded proof below. The prior numerical chain
and old command sequence in the historical section are not current launch
authority. No previous failure or missing closing proof is erased.

### Deliverables

- Preserve the original contract and evidence obligations through the named
  current owners; qualify no obligation from diagnostic or historical data.
- Reconcile the typed catalogue and replacement acceptance in 221.2, then admit
  the complete current evidence without duplicate training at consumer phases.

### Validation

Run the applicable complete CPU unit and negative-control stanzas only after
their real data/live prerequisites exist; the expanded sprint below specifies
its live or production-reader acceptance.

```bash
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-unit --linux-cpu
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-negative-controls --linux-cpu
```

### Remaining Work

- Complete the named prerequisites and expanded acceptance below.
- Reconcile all original owned obligations and obtain evidence-derived status;
  the historical text supplies no current closure claim.

## Sprint 280.2: Clean final CPU engineering gates [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `225.2`, Sprint `261.2`, Sprint `263.3`, Sprint `268.2`, Sprint `273.2`, Sprint `277.2`
**Docs to update**: `../documents/engineering/validation_execution.md`, `../documents/engineering/execution_resources.md`, `../documents/engineering/run_contract.md`, `../documents/engineering/unit_testing_policy.md`, `README.md`, `system-components.md`

### Objective

Complete the unchanged required CPU engineering suites after their genuine lane-data and live prerequisites exist. Hermetic request/event controls run earlier under the foundation owners; no unrelated hardware wait is imposed on them.

### Deliverables

- Classify every existing failure, including stale journal/schema/PlanId fixtures and lane registration, and repair the actual defect. No known-failure allowlist, blanket exclusion or skipped selected-substrate test is a standing pass.
- Preserve original request/event and live integration assertions while extending campaign-aware fixtures; retained old failures remain literal.
- Require full unfiltered unit, integration and negative suites on the final source, with every real live prerequisite supplied.

### Validation

These are acceptance requirements for the target implementation. They are not
passes from this documentation change. Targeted failing controls run first; the
complete applicable stanzas run only after their actual evidence prerequisites
exist. Commands use the explicit named context and task-specific approved bounds;
cluster-running work uses the separately admitted cluster/lifecycle profile.

1. All originally required cases remain registered in their correct real lanes; inventory proves no case disappears during the split.
2. Pass complete CPU suites after current journals/catalogues exist; a focused pass or historical journal does not stand for this obligation.

```bash
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-unit --linux-cpu
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-integration --linux-cpu
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml docs check
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml check-code
```

### Remaining Work

- Implement the deliverables after the listed prerequisites; retain every failed or incomplete observation in its original scope.
- Complete the listed acceptance in its declared evidence scope, retain the required records, and reconcile the source status catalogue before claiming closure.

## Retained Historical Contract and Evidence

The remainder records prior implementation, commands, status and failures. Its
claims retain their original source, policy and date. Superseded launch ordering,
resource rules and uninterrupted-process requirements do not override the current
sprints above. Preserve these receipts; do not execute a historical recipe as a
current authorized campaign.

## Retained Historical Phase State

⏸️ **Blocked**. Blocked by Phase 279 (Sprint 279.1), after Phase 278.

The request and event fixture suites are implemented and pass on the host and in
the `linux-cpu` container. This phase additionally consumes the three earlier
lane journals, owns their CPU-only aggregate, and retains the unchanged full CPU
unit and integration gates. Closure waits on Sprint `279.1` (see Remaining Work).

## Historical Sprint 280.1: RunContract Negative Controls - Request and Event Fixtures [⏸️ Blocked]

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

## Historical Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- [Validation execution](../documents/engineering/validation_execution.md),
  [execution resources](../documents/engineering/execution_resources.md),
  [run contract](../documents/engineering/run_contract.md), and
  [testing policy](../documents/engineering/unit_testing_policy.md).

**Product docs to create/update:**

- [Plan](README.md#validation-foundation-refactor), [overview](00-overview.md),
  [component inventory](system-components.md), and the corresponding lane
  report/portable evidence after actual qualification.

**Cross-references to add:**

- The current typed catalogue and [legacy removal ledger](legacy-tracking-for-deletion.md)
  name every changed owner and deprecated active path; original evidence is retained.

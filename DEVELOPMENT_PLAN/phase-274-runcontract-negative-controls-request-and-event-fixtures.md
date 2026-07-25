# Phase 274: RunContract Negative Controls - Request and Event Fixtures

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: RunContract Negative Controls - Request and Event Fixtures. Single-session phase migrated from legacy Sprint 32.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 272 (Sprint 272.1).

## Sprint 274.1: RunContract Negative Controls - Request and Event Fixtures [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Test/NegativeControls.hs`,
`src/JitML/Test/RunContract.hs`, `test/negative-controls/Main.hs`,
`test/unit/Main.hs`
**Blocked by**: Sprint `272.1`
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

### Remaining Work

- Blocked until Sprint `272.1` binds the versioned aggregate evidence to the
  exact admitted bytes graded by these controls.
- Add the invalid-request and invalid-event fixture suites.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

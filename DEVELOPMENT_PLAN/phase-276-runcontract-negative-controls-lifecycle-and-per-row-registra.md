# Phase 276: RunContract Negative Controls - Lifecycle and Per-Row Registration

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: RunContract Negative Controls - Lifecycle and Per-Row Registration. Single-session phase migrated from legacy Sprint 32.6 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 275 (Sprint 275.1).

## Sprint 276.1: RunContract Negative Controls - Lifecycle and Per-Row Registration [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Test/NegativeControls.hs`,
`src/JitML/Test/RunContract.hs`, `test/negative-controls/Main.hs`,
`test/unit/Main.hs`
**Blocked by**: Sprint `275.1`
**Docs to update**: `../README.md`,
`../documents/engineering/run_contract.md`,
`../documents/engineering/product_completion_contract.md`,
`../documents/engineering/unit_testing_policy.md`, `system-components.md`

### Objective

Prove that the contract handles the full run lifecycle — settlement, timeout,
cleanup, and terminal ordering — and make contract-negative coverage mandatory
for every product workflow row. This sprint closes the adversarial coverage for
[Exit Definition](README.md#exit-definition) items `31` and `32`.

### Deliverables

- Exercise successful and failed settlement, timeout, cleanup failure, workload-
  terminal-before-evidence, and evidence-before-workload-terminal orderings.
- Require every product workflow contract to register at least one negative
  control; accepting any known-invalid fixture fails the standing stanza.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Blocked until Sprint `275.1` lands the journal fixtures and reducer properties.
- Add the settlement/timeout/cleanup/terminal-order lifecycle suites.
- Make contract-negative coverage mandatory for every product row/workflow.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

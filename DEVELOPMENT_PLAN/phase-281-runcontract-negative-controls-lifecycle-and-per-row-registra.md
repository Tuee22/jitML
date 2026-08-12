# Phase 281: RunContract Negative Controls - Lifecycle and Per-Row Registration

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: RunContract Negative Controls - Lifecycle and Per-Row Registration. Single-session phase migrated from legacy Sprint 32.6 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 280 (Sprint 280.1).

## Sprint 281.1: RunContract Negative Controls - Lifecycle and Per-Row Registration [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Test/NegativeControls.hs`,
`src/JitML/Test/RunContract.hs`, `src/JitML/Test/LiveWorkflow.hs`,
`test/negative-controls/Main.hs`, `test/integration/Main.hs`,
`test/unit/Main.hs`
**Blocked by**: Sprint `280.1`
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
- Publish a correlated harness request through an established reply cursor
  rather than the diagnostic `ConsumerSessionConnected` socket-open event. This
  obligation transferred from Sprint `263.1` on 2026-08-11 under standards rule
  `M(a)`; it is an ownership transfer, not a blocker, and Phase `263` is `Done`
  on its retained fragment-issuance surface. Phase `262` already retired the
  shape on the production inference client; the remaining call sites are the
  `JitML.Test.LiveWorkflow` publish-gate observer and the two live integration
  observers. The replacement is a transport redesign rather than a deletion:
  `establishReplyCursor` admits only a `FromLatest`/`Owned` subscription minted
  from a broker admin CREATE, while `LiveWorkflow` must keep running over the
  non-broker `LocalEventSource`, so the harness transport needs an
  establishment step that is inert for local sources.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Blocked until Sprint `280.1` lands the journal fixtures and reducer properties.
- Add the settlement/timeout/cleanup/terminal-order lifecycle suites.
- Make contract-negative coverage mandatory for every product row/workflow.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

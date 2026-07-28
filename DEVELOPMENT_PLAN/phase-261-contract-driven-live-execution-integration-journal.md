# Phase 261: Contract-Driven Live Execution - Integration Journal

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Contract-Driven Live Execution - Integration Journal. Single-session phase migrated from legacy Sprint 28.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 252 (Sprint 252.1).

## Sprint 261.1: Contract-Driven Live Execution - Integration Journal [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `test/integration/Main.hs`,
`src/JitML/Test/WorkflowMatrix.hs`, `src/JitML/Test/RowAssertions.hs`,
`src/JitML/Product/Matrix.hs`
**Blocked by**: Sprint `252.1`
**Docs to update**: `../README.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/product_completion_contract.md`,
`../documents/engineering/run_contract.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Derive one scenario per `ProductRow` from the Phase `220` plan projection and
execute it through Sprint `160.1`'s `runLiveWorkflow` interpreter, so every
`linux-cpu` integration row cell closes only from measured completed evidence
rather than an artifact-only read, stdout prefix, declared test id, or green
exit code. This sprint owns the integration-side per-row portion of
[Exit Definition](README.md#exit-definition) items `31` and `34`. The binding
design is [README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Derive one scenario per `ProductRow` from the Phase `220` plan projection and
  execute it through Sprint `160.1`'s `runLiveWorkflow` interpreter.
- Require integration row reports to consume the completed evidence journal, not
  an artifact-only read, stdout prefix, declared test id, or green exit code.
- Bind training, checkpoint, inference, and negative-control evidence to the same
  `rowId`, `PlanId`, artifact hash, and substrate.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Blocked until Sprint `252.1` provides dimensionally correct RL plans and
  separated learning/evaluation evidence.
- Migrate all integration row cells and report projections to the scenario
  journal, retiring the metadata-only row helpers on the integration path.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

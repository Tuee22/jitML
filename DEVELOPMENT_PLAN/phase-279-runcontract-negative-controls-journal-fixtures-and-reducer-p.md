# Phase 279: RunContract Negative Controls - Journal Fixtures and Reducer Properties

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: RunContract Negative Controls - Journal Fixtures and Reducer Properties. Single-session phase migrated from legacy Sprint 32.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 278 (Sprint 278.1).

## Sprint 279.1: RunContract Negative Controls - Journal Fixtures and Reducer Properties [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Test/NegativeControls.hs`,
`src/JitML/Test/RunContract.hs`, `test/negative-controls/Main.hs`,
`test/unit/Main.hs`
**Blocked by**: Sprint `278.1`
**Docs to update**: `../documents/engineering/run_contract.md`,
`../documents/engineering/product_completion_contract.md`, `system-components.md`

### Objective

Prove that the contract rejects storage/completion journals that omit or corrupt
the opaque admitted identity, and that the event reducer stays total and
deterministic under event reordering and redelivery. This sprint owns the
journal-fixture and reducer-property portions of
[Exit Definition](README.md#exit-definition) items `31` and `32`.

### Deliverables

- Add journal fixtures that report storage success or caller-held completion but
  omit, substitute, or mismatch the opaque Store-admitted artifact identity;
  each must be rejected as ineligible without recreating admission logic in the
  harness.
- Property-test permutation invariance for independent events, idempotence for
  identical redelivery, deterministic rejection of conflicting duplicates, and
  exact missing-evidence diagnostics.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Blocked until Sprint `278.1` lands the request/event negative-control fixtures.
- Add the invalid-evidence journal suite (including
  storage-success-without-admission cases) and the reducer property suites.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

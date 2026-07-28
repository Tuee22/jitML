# Phase 288: Evidence-Typed Report Measurements

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Evidence-Typed Report Measurements. Single-session phase migrated from legacy Sprint 34.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 287 (Sprint 287.1).

## Sprint 288.1: Evidence-Typed Report Measurements [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Test/Report.hs`, `test/unit/Main.hs`
**Blocked by**: Sprint `287.1`
**Docs to update**: `../documents/engineering/run_contract.md`,
`../documents/engineering/unit_testing_policy.md`, `README.md`

### Objective

Represent report measurements as typed evidence and derive suite, lane, and
product counts from execution journals rather than a second post-test
measurement path. This sprint owns the [Exit Definition](README.md#exit-definition)
item `33` (lossless process and suite outcomes). It reads the journal-derived
status registry that Sprint `287.1` lands.

### Deliverables

- Represent report measurements as
  `NotRequested | Unavailable reason | Available evidence`; remove overlapping
  `Maybe` fields and unavailable sentinels.
- Derive suite counts from `Passed | Failed | NotRun` invocation results and
  lane/product counts from validated scenario journals.
- Remove post-test probes that manufacture a second measurement path; reports
  are projections of execution evidence already captured by the interpreter.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Blocked until Sprint `287.1` lands the journal-derived status registry the
  report projections read from.
- Replace ambiguous measurements, post-run probes, and fabricated counts with
  projections of execution evidence.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

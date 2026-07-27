# Phase 274: Journal-Derived Product Aggregation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Journal-Derived Product Aggregation. Single-session phase migrated from legacy Sprint 31.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 271 (Sprint 271.1).

## Sprint 274.1: Journal-Derived Product Aggregation [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Test/Report.hs`,
`DEVELOPMENT_PLAN/attestations/linux-cpu-report-card.md`,
`DEVELOPMENT_PLAN/attestations/linux-cuda-report-card.md`,
`DEVELOPMENT_PLAN/attestations/apple-silicon-report-card.md`
**Blocked by**: Sprint `271.1`
**Docs to update**: `../README.md`,
`../documents/engineering/product_completion_contract.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/run_contract.md`, `system-components.md`

### Objective

Join the three committed lane journals into one product result without
reconstructing evidence from prose, test ids, or post-hoc probes. This sprint
owns the aggregation portion of
[Exit Definition](README.md#exit-definition) item `34`.
The binding design is
[README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Decode and validate each committed lane fragment as a versioned scenario
  journal whose rows carry matching `rowId`, `PlanId`, opaque Store-admitted
  artifact identity, substrate, and completed evidence.
- Join the three fragments by product-row identity and fail on missing,
  duplicated, mismatched, failed, or not-run cells.
- Derive all aggregate counts and report measurements from the joined typed
  results; no prose table or hand-edited total can manufacture coverage.
- Keep aggregation `linux-cpu` only and consume the committed accelerator
  fragments without rerunning either accelerator.
- Emit the merged report and closure input consumed by the external-truth and
  status-governance phases.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Blocked until Sprint `271.1` publishes its refreshed contract-driven lane
  fragment containing admitted artifact identities. Sprint `267.1` supplies the
  CUDA fragment transitively, and Sprint `260.1` supplies the refreshed
  `linux-cpu` fragment.
- Implement typed journal decode/join and regenerate the aggregate report.
- Retire post-hoc/prose-fragment aggregation only after the join rejects all
  negative fixtures and the CPU-only validation passes.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

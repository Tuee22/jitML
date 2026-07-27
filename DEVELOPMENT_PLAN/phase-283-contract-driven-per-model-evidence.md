# Phase 283: Contract-Driven Per-Model Evidence

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Contract-Driven Per-Model Evidence. Single-session phase migrated from legacy Sprint 33.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 280 (Sprint 280.1).

## Sprint 283.1: Contract-Driven Per-Model Evidence [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Test/RowAssertions.hs`,
`src/JitML/Test/RunContract.hs`, `test/model-convergence/Main.hs`,
`src/JitML/Product/ExternalBars.hs`
**Blocked by**: Sprint `280.1`
**Docs to update**: `../README.md`,
`../documents/engineering/training_metrics_and_splits.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/product_completion_contract.md`,
`../documents/engineering/run_contract.md`, `system-components.md`

### Objective

Make every per-model convergence and inference-performance assertion consume an
opaque completed run-evidence value produced by the same plan and contract used
in live execution. This sprint owns the per-model portion of
[Exit Definition](README.md#exit-definition) item `31`.
The binding design is
[README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Drive every row from a validated plan and accept only
  `CompletedRunEvidence rowKind` from its exact contract.
- For RL, keep ordered learning-iteration summaries distinct from the exact
  keyed final `EvaluationSet`; neither may be substituted for the other.
- Require a validated non-empty seed cohort, finite per-seed measurements, exact
  seed coverage, and the independent external convergence criterion.
- Bind inference-performance measurement to the completed artifact and plan
  identity used by training, rather than reading an unrelated latest artifact.
- Preserve within-substrate deterministic rerun assertions while making missing,
  duplicate, or cross-plan evidence a typed failure.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Blocked until Sprint `278.1` establishes the contract's adversarial acceptance
  boundary.
- Migrate all per-model assertions to completed run evidence and separate RL
  learning/evaluation observations.
- Revalidate every ProductRow before returning this phase to Done.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

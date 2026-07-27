# Phase 251: Typed Measured Counters and Evidence Separation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Typed Measured Counters and Evidence Separation. Single-session phase migrated from legacy Sprint 25.6 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 250 (Sprint 250.1).

## Sprint 251.1: Typed Measured Counters and Evidence Separation [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/App.hs`, `src/JitML/RL/Framework.hs`,
`src/JitML/RL/Algorithms/Common.hs`, `src/JitML/Proto/Rl.hs`,
`test/rl-canonicals/Main.hs`
**Blocked by**: Sprint `250.1`
**Docs to update**: `../documents/engineering/training_metrics_and_splits.md`,
`../documents/engineering/product_completion_contract.md`,
`../documents/engineering/run_contract.md`, `../README.md`

### Objective

Have trainers return measured typed transition/update counters instead of caller
reconstruction, and publish an ordered `IterationSummary` learning curve
separately from a keyed, exact `EvaluationSet`, so training, learning-curve, and
final-evaluation quantities cannot be confused. This sprint closes the RL evidence
portion of [Exit Definition](README.md#exit-definition) items `30` and `31`.

### Deliverables

- Have trainers return measured typed transition/update counters rather than
  reconstructing them in callers.
- Publish ordered `IterationSummary` learning evidence separately from a keyed,
  exact `EvaluationSet`; medians require non-empty finite measurements.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Remove the reconstructed counters in callers once trainers emit the typed
  measured counters, and land the `IterationSummary`/`EvaluationSet` separation
  in the RL report card.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

# Phase 282: Inference-Performance & Determinism

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Inference-Performance & Determinism. Single-session phase migrated from legacy Sprint 33.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 282.1: Inference-Performance & Determinism [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Test/RowAssertions.hs`, `test/model-convergence/Main.hs`, `src/JitML/Product/ExternalBars.hs`
**Docs to update**: `../documents/engineering/training_metrics_and_splits.md`, `system-components.md`

### Objective

Every row reports a non-wall-clock inference-performance metric against a committed
floor, reproduced bit-identically on re-run.

### Deliverables

- SL rows assert examples/sec throughput ≥ floor; RL rows assert
  env-steps-to-threshold ≤ ceiling (sample efficiency); both from real inference on the
  trained artifact.
- A same-seed re-run reproduces the metric bit-identically (determinism contract).
- The performance floors live in `ExternalBars.hs`, never derived from the measured
  value.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

- Implemented the inference-performance assertions and floors.
- Revalidated the non-wall-clock inference-performance floors and same-seed
  determinism contract at the widened/vectorized regime:
  `docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu`
  passed **111 / 111** on 2026-07-10.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

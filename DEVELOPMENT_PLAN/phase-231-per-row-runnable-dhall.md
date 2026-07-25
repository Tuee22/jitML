# Phase 231: Per-Row Runnable Dhall

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Per-Row Runnable Dhall. Single-session phase migrated from legacy Sprint 22.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 231.1: Per-Row Runnable Dhall [✅ Done]

**Status**: Done
**Implementation**: `experiments/mnist.dhall`, `experiments/cartpole.dhall`, `src/JitML/Experiment/Product.hs`, `src/JitML/Experiment/Overrides.hs`, `src/JitML/App.hs`, `test/unit/Main.hs`
**Docs to update**: `../documents/engineering/training_workloads.md`

### Objective

Every product row has a checked-in or reflected Dhall `experimentConfig` that is
addressable and runnable through `jitml`. A row's `experimentConfig` field in the
registry points at a config that resolves, type-checks, and drives the row's
training command without a missing-file reference.

### Deliverables

- Every `ProductRow` resolves an `experimentConfig` runnable through
  `jitml train`, `jitml rl train`, `jitml rl alphazero self-play`, or
  `jitml tune`, checked into `experiments/` or produced by a reflected config
  generator over the registry.
- A unit test loads and type-checks the config for every product row and fails on
  a row whose config is missing, unparseable, or references a non-existent
  dataset/environment key; generated command examples never reference a missing
  file.
- CLI overrides in `src/JitML/Experiment/Overrides.hs` apply to the resolved
  config without replacing the surrounding Dhall record, so a row runs with its
  documented defaults unless a flag overrides a single field.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

**Result (2026-07-02)**:
- `docker compose run --rm jitml jitml test jitml-unit --linux-cpu` — passed,
  265 / 265 tests.
- `docker compose run --rm jitml jitml docs check` — passed.
- `docker compose run --rm jitml jitml check-code` — passed.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

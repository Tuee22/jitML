# Phase 185: Live linux-cuda Exercise of the Reopened Workflows

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Live linux-cuda Exercise of the Reopened Workflows. Single-session phase migrated from legacy Sprint 15.18 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 185.1: Live linux-cuda Exercise of the Reopened Workflows [✅ Done]

**Status**: Done
**Docs to update**: `system-components.md`

### Objective

Exercise every reopened real workflow on the **linux-cuda** lane (real
cuBLAS/cuDNN kernels via the GPU-attached `jitml-cuda` service) against a live
cluster, with `-fcuda` so the CUDA bindings link.

### Current Validation State

- Host and `jitml-cuda` see the NVIDIA GeForce RTX 5090, CUDA 12.8, driver
  `570.211.01`.
- `docker compose run --rm jitml-cuda jitml bootstrap --linux-cuda` executed
  **83** fresh-data rollout steps.
- Full `cabal test -fcuda jitml-integration --test-show-details=direct` passed
  **67 / 67**.
- `jitml test jitml-e2e --linux-cuda` passed **20 / 20**.
- `jitml test jitml-daemon-lifecycle --linux-cuda` passed **32 / 32**,
  including the rendered workload Job `runtimeClassName: nvidia` regression.
- Live CUDA Playwright value assertions passed **9 / 9** against the published
  demo edge.

### Remaining Work

- None for the linux-cuda live lane.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

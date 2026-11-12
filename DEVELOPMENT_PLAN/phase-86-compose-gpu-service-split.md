# Phase 86: Compose GPU Service Split

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Compose GPU Service Split. Single-session phase migrated from legacy Sprint 7.9 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Current execution ownership

**Historical record; no current execution gate.** Phases 1–289 retain their
original contracts, statuses and receipts below. Their former order, dependencies
and current-sounding statements are historical. They do not gate the new
[numerical execution sequence](ordered-execution-plan.md). No historical failure
is erased and no historical Done is promoted to current qualification.

The original recorded scope remains historical; no new obligation or current
closure is inferred from its prior status. A discovered defect reopens its
current successor owner under the [plan standards](development_plan_standards.md).

## Historical plan and evidence

## Phase State

✅ **Done**.

## Sprint 86.1: Compose GPU Service Split [✅ Done]

**Status**: Done (reopened and re-closed 2026-06-04).

### Intent

Keep the container-only code-quality path runnable on non-NVIDIA hosts while
preserving live in-container CUDA validation. The default `jitml` service is the
headless host-networked command wrapper; `jitml-cuda` is the GPU-enabled
companion for direct CUDA tests.

### Implementation

- `compose.yaml` now factors the shared `jitml:local` image/build/mount/network
  settings into one service template.
- `jitml` uses the shared template with no GPU request, so
  `docker compose run --rm jitml jitml check-code` reaches the CLI on CPU-only
  hosts.
- `jitml-cuda` uses the same image and mounts plus `gpus: all`, preserving the
  live CUDA validation path for commands that need device exposure in the outer
  container.

### Validation

1. `docker compose build jitml` passes after the no-`allow-newer` dependency
   replacement and runs `jitml check-code` during image construction.
2. A fresh `docker compose run --rm jitml jitml check-code` rebuilds/exports
   `jitml:local`, builds the PureScript bundle, and completes the final
   headless command with `check-code: ok` without requesting a GPU device
   driver.

### Remaining Work

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

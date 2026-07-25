# Phase 209: Apple Placement Ledger Walk-Down and Final Handoff

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Apple Placement Ledger Walk-Down and Final Handoff. Single-session phase migrated from legacy Sprint 17.7 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 209.1: Apple Placement Ledger Walk-Down and Final Handoff [✅ Done]

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`,
`DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`,
`DEVELOPMENT_PLAN/system-components.md`
**Docs to update**: `../README.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`,
`DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Close the Apple placement reopen by moving the stale Kubernetes-Job placement row
to `Completed`, confirming the full Apple lane passes with host-resident Metal
execution, and restoring the final-handoff state.

### Deliverables

- `legacy-tracking-for-deletion.md` Pending Removal is empty after the Apple Job
  placement branch is deleted.
- `README.md`, `00-overview.md`, and `system-components.md` agree on the reopened
  and re-closed phase statuses.
- Final validation evidence names the Apple host-resident Training/RL/Tune path,
  the no-Apple-Metal-Job assertion, and the unchanged Linux CPU/CUDA placement
  behavior.

### Validation

- The Phase `16` Apple-Silicon lane test passed after Sprint `16.10`; all eight
  report stanzas rendered PASS, including `jitml-integration` **71 / 71** and
  `jitml-backends` **17 / 17**.
- Focused `linux-cpu` live dispatch/convergence selectors passed during Sprint
  `12.12`, preserving Linux Job-backed placement. The CUDA lane remains closed
  from the real NVIDIA-host validation recorded in Phase `15`; no CUDA source
  or contract changed in the Apple placement walk-down.
- `legacy-tracking-for-deletion.md` Pending Removal is empty again after moving
  the Apple Metal-backed Training/RL/Tune Kubernetes Job placement row to
  `Completed`.
- `docker compose run --rm jitml jitml docs check`,
  `docker compose run --rm jitml jitml check-code`, and `git diff --check` pass.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

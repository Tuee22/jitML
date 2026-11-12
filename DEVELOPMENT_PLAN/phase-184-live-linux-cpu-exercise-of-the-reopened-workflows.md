# Phase 184: Live linux-cpu Exercise of the Reopened Workflows

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Live linux-cpu Exercise of the Reopened Workflows. Single-session phase migrated from legacy Sprint 15.17 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

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

## Sprint 184.1: Live linux-cpu Exercise of the Reopened Workflows [✅ Done]

**Status**: Done
**Docs to update**: `system-components.md`

### Objective

Exercise every reopened real workflow (Phases `8`–`11`) on the **linux-cpu**
lane against a live cluster through the `WorkflowMatrix` (Sprint `12.11`): live
`jitml train` (device-backed SL classifier), `jitml rl train` (on-device
trainers), `jitml rl eval` / `rollout`, `jitml tune` (real objective), `jitml
inference run` (weighted kernel), and AlphaZero self-play — each producing real
measured output that clears its in-code threshold.

### Validation

- `jitml bootstrap --linux-cpu` then
  `docker compose run --rm jitml jitml test jitml-e2e --linux-cpu` and the
  `jitml-integration -p Live` matrix cells, all PASS for real.

### Current Validation State

- `docker compose run --rm jitml jitml bootstrap --linux-cpu` executed **83**
  clean-data rollout steps after preserving the stale PV tree as
  `.data-preserved-20260611-1709`.
- Focused live PPO convergence passed on the rebuilt image.
- Full `jitml-integration` passed **67 / 67** and `jitml-e2e --linux-cpu`
  passed **20 / 20**.

### Remaining Work

- None for the linux-cpu live lane. The non-Dense SL and Phase `9`
  device-backed MCTS/tuning code follow-ons remain in their owning phases, not
  in Sprint `15.17`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

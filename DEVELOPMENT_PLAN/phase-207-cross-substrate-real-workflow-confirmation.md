# Phase 207: Cross-Substrate Real-Workflow Confirmation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Cross-Substrate Real-Workflow Confirmation. Single-session phase migrated from legacy Sprint 17.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 207.1: Cross-Substrate Real-Workflow Confirmation [✅ Done]

**Status**: Done
**Docs to update**: `system-components.md`

### Objective

Confirm that every reopened real workflow (Phases `8`–`11`) runs for real on all
three substrates and that the within-substrate determinism contract holds for
each (two fresh same-substrate / same-seed runs are bit-identical), via the
`jitml test all` report card reading the real measured metrics per lane.

### Validation State (2026-06-12)

- The linux-cpu and linux-cuda live lanes completed on the CUDA machine on
  2026-06-11; Phase `12` live WorkflowMatrix completed on linux-cpu on
  2026-06-12.
- Phase `16` Sprint `16.9` completed the apple-silicon fixed-bridge lane:
  `jitml-backends` 17 / 17, `jitml-e2e` 20 / 20, and live `WorkflowMatrix`
  1 / 1 against a published Apple cluster.
- `docker compose build jitml` passed after the fixed-bridge source and docs
  changes; the image-local gate reported `check-code: ok` and the PureScript
  bundle rebuilt successfully.
- `docker compose run --rm jitml jitml docs check`,
  `docker compose run --rm jitml jitml check-code`, and `git diff --check`
  passed after the final validation sweep.

### Remaining Work

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

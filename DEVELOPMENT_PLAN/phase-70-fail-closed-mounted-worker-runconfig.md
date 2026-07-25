# Phase 70: Fail-Closed Mounted Worker `RunConfig`

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Fail-Closed Mounted Worker RunConfig. Single-session phase migrated from legacy Sprint 5.17 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 70.1: Fail-Closed Mounted Worker `RunConfig` [✅ Done]

**Status**: Done (closed 2026-06-30)
**Implementation**: `src/JitML/Service/RunConfig.hs`, `src/JitML/App.hs`,
`src/JitML/Service/Workload.hs`, worker config tests
**Docs to update**: `documents/engineering/daemon_architecture.md`,
`documents/engineering/training_workloads.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Make mounted typed worker configuration authoritative. A daemon-dispatched Job
with a present but malformed `RunConfig.dhall` must fail with a typed
configuration error instead of silently running a default or env-derived workload.

### Deliverables

- Replace the `tryLoad*RunConfig` "decode error = Nothing" behaviour with a
  result that distinguishes `missing` from `decode failed`.
- Preserve env/default fallbacks only for explicit local developer invocations
  where `/etc/jitml/run/RunConfig.dhall` does not exist.
- Route malformed mounted Training/Tune/RL config to `AppError InvalidConfig`
  before any dataset fetch, trial selection, environment step, checkpoint write,
  or Pulsar publication.
- Add regression coverage for malformed mounted `TrainingRunConfig`,
  `TuneRunConfig`, and `RlRunConfig` bytes.

### Validation

- `docker compose run --rm jitml jitml test jitml-unit --linux-cpu` passed
  **239 / 239**, including the Sprint `5.17` malformed mounted RunConfig
  regression for Training/Tune/RL variants.
- `docker compose run --rm jitml jitml test jitml-daemon-lifecycle --linux-cpu`
  passed **32 / 32**, preserving rendered workload Job and RunConfig behavior.
- `docker compose run --rm jitml jitml test jitml-integration --linux-cpu`
  passed **77 / 77**, including **19 / 19** live cases against the `linux-cpu`
  cluster publication.
- `docker compose run --rm jitml jitml check-code` passed (`check-code: ok`).

### Remaining Work

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

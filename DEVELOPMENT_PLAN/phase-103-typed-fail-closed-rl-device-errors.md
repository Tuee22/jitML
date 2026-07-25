# Phase 103: Typed Fail-Closed RL Device Errors

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Typed Fail-Closed RL Device Errors. Single-session phase migrated from legacy Sprint 8.15 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 103.1: Typed Fail-Closed RL Device Errors [✅ Done]

**Status**: Done (closed 2026-06-29)
**Implementation**: `src/JitML/RL/Algorithms/DqnTrainer.hs`,
`src/JitML/RL/Algorithms/QrDqnTrainer.hs`,
`src/JitML/RL/Algorithms/HerTrainer.hs`,
`src/JitML/RL/Algorithms/ContinuousTrainer.hs`, `src/JitML/App.hs`
**Docs to update**: `documents/engineering/training_workloads.md`,
`documents/engineering/haskell_code_guide.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`, `system-components.md`

### Objective

Preserve the Sprint `8.11` fail-closed device policy without using untyped
bottoms. Mid-run device failures after a successful `probeMlpDevice` remain fatal
to the run, but they return through the same `Either` / `InvalidConfig` path as
upfront substrate unavailability.

### Deliverables

- Change the DQN, QR-DQN, HER, and continuous actor-critic device update helpers
  to return typed failure values for forward, batch-gradient, and input-gradient
  errors.
- Change the corresponding `train*OnDevice` entrypoints and `runTrainerEpisodes`
  callers so post-probe failures become `Left Text` / `InvalidConfig` with no
  partial print or publication.
- Keep ARS as the sole no-MLP exception; no pure-Haskell fallback is introduced
  for MLP-backed trainers.
- Add regression tests that inject failing `MlpDevice` operations and assert
  typed failure rather than process termination.

### Validation

- `docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`
- `docker compose run --rm jitml jitml test jitml-backends --linux-cpu`
- `docker compose run --rm jitml jitml check-code`

### Remaining Work

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

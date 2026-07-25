# Phase 94: RL Training Plan Surface

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: RL Training Plan Surface. Single-session phase migrated from legacy Sprint 8.6 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 94.1: RL Training Plan Surface [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface only. Daemon `RlHandler`
plumb-through, live reward-threshold + checkpoint/resume equality
assertion migrated to Phase `15` Sprints `15.3` / `15.6`.
**Implementation**: `src/JitML/App.hs`, `src/JitML/Plan/Plan.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Expose the current RL training plan surface. Real typed RL training pipelines
are closed by the later no-caveat runtime and per-lane closure phases.

### Deliverables

- `src/JitML/Plan/Plan.hs` renders the current `jitml rl train` plan steps.
- `src/JitML/App.hs` dispatches `jitml rl train`, `jitml rl eval`, and
  `jitml rl rollout` to local summaries.
- Historical Sprint `8.5` supplied the then-current payload-hash deduplication
  helper for later RL event consumers; Sprint `8.16` replaces it with
  plan/kind/key semantic identity after strict typed decode.
- `src/JitML/RL/Loop.hs` declares `RLLoop`, `RLConfig`, `EpisodeResult`,
  and `RLLoopResult`. `runRLLoop` walks the algorithm × policy ×
  environment cohort through the `RLRunPhase` plan, accumulating
  per-episode rewards from the deterministic environment step helper
  and recording the rollout in a typed `ReplayBuffer`.
- Historical Sprint `8.4` note: daemon-backed training execution against live
  Pulsar / live MinIO was later implemented for the scoped workflow surface;
  Sprint `9.12` / Phase `13` now expand the same standard to the full
  no-caveat RL matrix.

### Validation

1. `jitml rl train --dry-run experiments/cartpole.dhall` emits the typed
   plan.
2. `jitml rl train experiments/cartpole.dhall` prints the algorithm
   catalog summary.
3. `cabal test jitml-rl-canonicals` verifies the deterministic local
   `RLLoop` records rollout transitions into its `ReplayBuffer`.
4. Transferred live validation: a real `RLLoop` executes against the daemon
   for one cartpole episode, reaches the reward threshold, and the
   resulting checkpoint resumes bit-deterministically to the same reward.

### Remaining Work

- No sprint-owned code-surface Remaining Work remains. The daemon-side
  `RlHandler` plumb-through, the live broker + capability classes, and
  the live reward-threshold + checkpoint/resume equality assertion are
  owned by
  [phase-15-linux-cuda-and-cluster-closure.md](README.md#legacy-to-new-phase-map)
  Sprints `15.3` and `15.6`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

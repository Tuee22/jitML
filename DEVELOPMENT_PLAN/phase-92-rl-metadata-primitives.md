# Phase 92: RL Metadata Primitives

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: RL Metadata Primitives. Single-session phase migrated from legacy Sprint 8.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 92.1: RL Metadata Primitives [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface only. Live HTTP MinIO
wiring of `AsyncSink` migrated to Phase `15` Sprints `15.2` / `15.7`.
**Implementation**: `src/JitML/RL/Algorithms.hs`,
`src/JitML/RL/Framework.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Stand up the local metadata primitives consumed by the Phase `9` algorithm
catalog and the GADT-indexed lifecycle surfaces required by the doctrine.

### Deliverables

- `AlgorithmFamily` enumerates `OnPolicy`, `OffPolicy`, `Specialized`, and
  `SelfPlay`.
- `RLAlgorithm` records `algorithmName`, `algorithmFamily`, and
  `algorithmReplayBased`.
- `algorithmCatalog` contains the metadata rows consumed by the
  CLI and tests.
- `src/JitML/RL/Framework.hs` defines the local `TrainingLifecycle`,
  `TuneSweepLifecycle`, and (after Sprint 8.7) `RLRunLifecycle` GADT
  lifecycle surfaces plus the matching `rlRunPlan`.
- `src/JitML/RL/Policy.hs` declares the runtime `Policy` record with
  `PolicyShape`, `ParamRef` references, the substrate binding, and the
  `KernelHandle` model id.
- `src/JitML/RL/VecEnv.hs` provides parallel environment stepping
  (`VecEnv`, `vecEnvStep`, `vecEnvTrajectory`).
- `src/JitML/RL/Buffer.hs` provides the `ReplayBuffer` with
  deterministic insertion + sample ordering, supporting both
  `OnPolicyRollout` and `OffPolicyReplay` modes.
- `JitML.RL.AsyncBuffer` provides the typed `AsyncBuffer` /
  `AsyncSink` wrapper around `ReplayBuffer`: `insertAsync` updates the
  buffer in-place and spawns an async write through the sink, while
  `drainAsync` waits for pending writes at episode-end / drain boundaries.
  `jitml-unit` covers deterministic in-order drain behaviour and
  `jitml-integration` covers a filesystem-backed `HasMinIO` sink.

### Validation

1. `cabal test jitml-rl-canonicals` verifies the algorithm catalog
   contains representative expected algorithms.
2. `jitml-unit` verifies the run-plan rendering.
3. Transferred live validation: real `Policy`, `VecEnv`, replay/rollout
   buffers, and `Async` write discipline are exercised end-to-end against
   running environments through the daemon.

### Remaining Work

- No sprint-owned code-surface Remaining Work remains. The live HTTP
  MinIO wiring of `AsyncSink` is owned by
  [phase-15-linux-cuda-and-cluster-closure.md](README.md#legacy-to-new-phase-map)
  Sprints `15.2` and `15.7`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

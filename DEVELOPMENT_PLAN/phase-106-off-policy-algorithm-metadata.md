# Phase 106: Off-Policy Algorithm Metadata

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Off-Policy Algorithm Metadata. Single-session phase migrated from legacy Sprint 9.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 106.1: Off-Policy Algorithm Metadata [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface only. Per-algorithm
run-to-run determinism plus rule-conformance properties closed on
2026-05-24 for DQN, QR-DQN (cartpole) and DDPG, TD3, SAC (mountain-car)
via `AlgorithmModule.moduleRolloutGenerator` re-running the rollout
in-process and asserting bit-identity (no committed rollout-value files
per [../README.md → Snapshot targets → Numerical-fixture
prohibition](../README.md#snapshot-targets)). Real cuDNN deterministic
algorithm pin executed against off-policy network forward /
target-network update migrated to Phase `15` Sprint `15.8`.
**Implementation**: `src/JitML/RL/Algorithms.hs`,
`src/JitML/RL/Algorithms/{Dqn,QrDqn,Ddpg,Td3,Sac}.hs`,
`test/rl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Land the current off-policy algorithm metadata rows.

### Deliverables

- `algorithmCatalog` includes off-policy rows for `DQN`, `QR-DQN`, `DDPG`,
  `TD3`, and `SAC`.
- Each row records the `OffPolicy` family and `algorithmReplayBased = True`.
- The five checked-in off-policy algorithm modules expose typed
  deterministic hyperparameter rows and per-seed transcripts.
- Replay-buffer primitives are present in `JitML.RL.Buffer`; real
  network update code and full per-algorithm run-to-run trajectory
  determinism coverage are closed by the later no-caveat runtime and
  per-lane closure phases.

### Validation

1. `algorithmCatalog` exposes the five checked-in off-policy rows.
2. Transferred live validation: each off-policy algorithm has a dedicated
   module with real replay-buffer code and per-seed transcript
   determinism asserted by run-to-run equality (no committed transcript
   files per [../README.md → Snapshot targets → Numerical-fixture
   prohibition](../README.md#snapshot-targets)).

### Remaining Work

- Per-algorithm run-to-run determinism closed on 2026-05-24 for DQN,
  QR-DQN (cartpole) and DDPG, TD3, SAC (mountain-car) keyed through
  `AlgorithmModule.moduleRolloutGenerator` and asserted by running the
  rollout twice in-process and asserting bit-identity between the two
  outputs plus rule-conformance properties; no `test/golden/rl/...`
  files are committed.
- Wiring the deterministic-cuDNN algorithm pin into the real off-policy
  network forward / target-network update path is owned by
  [phase-15-linux-cuda-and-cluster-closure.md](README.md#legacy-to-new-phase-map)
  Sprint `15.8`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

# Phase 9: RL Algorithm Catalog, AlphaZero, and Hyperparameter Tuning

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-8-supervised-and-rl-framework.md](phase-8-supervised-and-rl-framework.md),
[phase-10-checkpointing-and-inference.md](phase-10-checkpointing-and-inference.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Stand up the current local RL algorithm metadata catalog, Connect
> 4 / AlphaZero transcript helpers, canonical game metadata, and deterministic
> hyperparameter tuning catalogs. The target runtime extends these surfaces into
> one module per algorithm, persistent MCTS state, live trial storage/resume, and
> daemon-backed training.

## Phase Status

✅ **Done** for the local RL algorithm catalog, AlphaZero transcript, and tuning
surfaces. The algorithm catalog consumes the RL framework primitives from Phase
`8`. AlphaZero's persistent MCTS state borrows the engineering arc from a
sibling MCTS project. The tuner consumes both SL and RL training surfaces.

### Current Implementation Scope

The current worktree implements a local `RLAlgorithm` catalog with family/replay
metadata, a Dhall schema mirror/audit at `dhall/rl/Schema.dhall`, deterministic
trajectory generation with a PPO/CartPole golden fixture, Connect 4
move/transcript helpers in `src/JitML/RL/AlphaZero.hs`, and deterministic
sampler/scheduler/pruner catalogs in `src/JitML/Tune/Catalog.hs`. It does not
yet implement one module per RL algorithm, full per-algorithm golden RL fixture
trees, perfect-information game typeclasses, two-headed networks, persistent
MCTS search, MinIO trial storage, or live tuner resume.

## Phase Summary

This phase currently delivers local RL algorithm metadata, Connect 4 transcript
helpers, and deterministic tuning catalogs. The target phase grows those
surfaces into one module per algorithm, a persistent AlphaZero/MCTS sub-stack,
and a typed sweep manager that drives SL, RL, or AlphaZero training under a
sampler × scheduler × pruner Dhall.

## Sprint 9.1: On-Policy Algorithm Metadata ✅

**Status**: Done
**Implementation**: `src/JitML/RL/Algorithms.hs`,
`test/rl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Land the current on-policy algorithm metadata rows. Real algorithm modules and
full golden trajectory fixture coverage remain target work.

### Deliverables

- `algorithmCatalog` includes on-policy rows for `PPO`, `A2C`, `TRPO`,
  `MaskablePPO`, and `RecurrentPPO`.
- Each row records the `OnPolicy` family and `algorithmReplayBased = False`.
- `renderAlgorithmCatalog` renders the table from the local metadata list.

### Validation

1. `cabal test jitml-rl-canonicals` verifies representative catalog entries.
2. Live reward thresholds and trajectory fixtures remain target validation.

## Sprint 9.2: Off-Policy Algorithm Metadata ✅

**Status**: Done
**Implementation**: `src/JitML/RL/Algorithms.hs`,
`test/rl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Land the current off-policy algorithm metadata rows.

### Deliverables

- `algorithmCatalog` includes off-policy rows for `DQN`, `QR-DQN`, `DDPG`,
  `TD3`, and `SAC`.
- Each row records the `OffPolicy` family and `algorithmReplayBased = True`.
- Replay buffers, algorithm-specific modules, and full golden trajectory
  fixture coverage are not present in the current tree.

### Validation

1. `algorithmCatalog` exposes the five checked-in off-policy rows.
2. Off-policy training determinism remains target validation.

## Sprint 9.3: Specialised Algorithm Metadata ✅

**Status**: Done
**Implementation**: `src/JitML/RL/Algorithms.hs`,
`test/rl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Land the current specialised algorithm metadata rows.

### Deliverables

- `algorithmCatalog` includes specialised rows for `CrossQ`, `TQC`, `ARS`,
  and `HER`.
- `CrossQ`, `TQC`, and `HER` are marked replay-based; `ARS` is not.
- The generated training-workload catalog table is actively rendered from the
  current Haskell catalog by `jitml docs generate`.

### Validation

1. `algorithmCatalog` exposes the four checked-in specialised rows.
2. `jitml docs check` validates the generated catalog table.

## Sprint 9.4: Local RL Canonical Tests ✅

**Status**: Done
**Implementation**: `test/unit/Main.hs`, `test/integration/Main.hs`,
`test/rl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Stitch the current RL metadata and deterministic trajectory helper into the
dedicated local RL canonical stanza.

### Deliverables

- `test/rl-canonicals/Main.hs` verifies representative algorithm names across
  the local metadata catalog.
- The stanza asserts `deterministicTrajectory "PPO" 42` is stable and matches
  the current PPO/CartPole golden fixture.
- The stanza also checks the current Connect 4 transcript helper keeps moves
  within legal column bounds.
- `test/golden/rl/ppo/cartpole/trajectory.txt` pins the current local
  PPO/CartPole deterministic trajectory; full per-algorithm fixture trees
  remain target work.

### Validation

1. `cabal test jitml-rl-canonicals` exits `0` for the current local body.
2. Full per-algorithm reward/trajectory fixture coverage remains target
   validation.

## Sprint 9.5: AlphaZero Connect 4 Transcript Surface ✅

**Status**: Done
**Implementation**: `src/JitML/RL/AlphaZero.hs`,
`test/rl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`,
`documents/engineering/determinism_contract.md`

### Objective

Land the current Connect 4 transcript, two-headed-network metadata, canonical
perfect-information game catalog, and arena summary surface used by the local
AlphaZero summary.

### Deliverables

- `GameState` carries `gameName`, `gameMoves`, and `gameCurrentPlayer`.
- `MctsState` exists as a small metadata record with visit count and prior
  seed; it is not a persistent search tree.
- `initialConnect4`, `applyMove`, and `selfPlayTranscript` provide a
  deterministic local transcript helper.
- `PerfectInformationGame`, `TwoHeadedNetwork`, `connect4Network`,
  `ArenaSummary`, and `arenaWinRate` provide the local game/network/arena
  summary surface.
- `test/rl-canonicals/Main.hs` asserts generated Connect 4 moves stay in
  columns `0` through `6`.
- Persistent `Mcts.hs`, `SelfPlay.hs`, `Arena.hs`, and self-play buffers remain
  target runtime validation.

### Validation

1. `selfPlayTranscript` is deterministic for a fixed seed.
2. `cabal test jitml-rl-canonicals` checks legal Connect 4 columns.
3. `jitml-unit` verifies the local game catalog, network metadata, and arena
   win-rate helper.

## Sprint 9.6: Connect 4 Local Game Surface ✅

**Status**: Done
**Implementation**: `src/JitML/RL/AlphaZero.hs`,
`src/JitML/Web/Contracts.hs`, `test/rl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Land the current Connect 4 local game surface, canonical adversarial-game
catalog, and corresponding browser-contract endpoint metadata.

### Deliverables

- `src/JitML/RL/AlphaZero.hs` names the local game `connect4`.
- `applyMove` normalizes moves into legal Connect 4 columns.
- `src/JitML/Web/Contracts.hs` includes the `Connect4Move` endpoint metadata
  used by the frontend scaffold.
- `canonicalGames` lists Connect 4, Othello, Hex, and Gomoku as local
  `PerfectInformationGame` metadata rows.
- `test/golden/alphazero/connect4-transcript.txt` pins the current local
  Connect 4 transcript shape. Full adversarial-game replay fixture trees remain
  target work.

### Validation

1. `cabal test jitml-rl-canonicals` validates the current Connect 4 move
   bounds.
2. Full golden replay codec validation remains target work.

## Sprint 9.7: Hyperparameter Tuning (Sampler × Scheduler × Pruner) ✅

**Status**: Done
**Implementation**: `src/JitML/Tune/Catalog.hs`,
`src/JitML/App.hs`, `test/hyperparameter/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Land the current deterministic sampler × scheduler × pruner catalogs,
trial-storage key helpers, resume equality summary, and `jitml tune` local
summary.

### Deliverables

- `Sampler` enumerates `Sobol`, `Random`, `GeneticAlgorithm`, and
  `EvolutionStrategies`.
- `Scheduler` enumerates `Fifo`, `SuccessiveHalving`, `Hyperband`, and `ASHA`.
- `Pruner` enumerates `NoPruner`, `MedianPruner`, and `PercentilePruner`.
- `deterministicTrials` emits normalized deterministic trial values for the
  current sampler set.
- `test/golden/tune/` pins the current Sobol and GeneticAlgorithm trial
  streams.
- `trialStorageKey`, `resumeMatchesFullRun`, and
  `renderTrialResumeSummary` provide the local trial persistence/resume
  surface.
- `jitml tune <tune-dhall>` is Plan/Apply-capable and currently prints four
  deterministic Sobol trial values.
- Dhall `Some Tuning`, generated proto bindings, and live MinIO persistence
  remain target runtime validation.

### Validation

1. `jitml tune --dry-run experiments/mnist-tune.dhall` emits the typed plan.
2. `cabal test jitml-hyperparameter` verifies the sampler, scheduler, and
   pruner axes are populated and deterministic.
3. `jitml-unit` verifies the local trial key and resume-equality helpers.

## Doctrine Sections Cited

- [../HASKELL_CLI_TOOL.md → Command Topology](../HASKELL_CLI_TOOL.md) (Sprint 9.7 — `jitml tune` command leaf)
- [../HASKELL_CLI_TOOL.md → Plan / Apply](../HASKELL_CLI_TOOL.md) (Sprint 9.7 — current dry-run / plan-file surface)
- [../HASKELL_CLI_TOOL.md → Test Organization](../HASKELL_CLI_TOOL.md) (Sprints 9.4, 9.7 — dedicated local RL and hyperparameter stanzas)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/training_workloads.md` — current RL algorithm
  metadata catalog, Dhall mirror, PPO/CartPole golden trajectory fixture,
  Connect 4 transcript helper, and tuner catalog; target algorithm modules,
  AlphaZero/MCTS runtime, adversarial games, and full tuner storage/resume
  surface.
- `documents/engineering/determinism_contract.md` — current deterministic
  local trajectory/transcript helpers and target AlphaZero
  deterministic-stochasticity narrative.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → Training Workload Surfaces` rows for RL catalog,
  AlphaZero, and tuning remain aligned with `src/JitML/RL/Algorithms.hs`,
  `src/JitML/RL/AlphaZero.hs`, and `src/JitML/Tune/Catalog.hs`.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)

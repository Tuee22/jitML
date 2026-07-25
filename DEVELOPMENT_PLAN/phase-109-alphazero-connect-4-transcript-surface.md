# Phase 109: AlphaZero Connect 4 Transcript Surface

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: AlphaZero Connect 4 Transcript Surface. Single-session phase migrated from legacy Sprint 9.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 109.1: AlphaZero Connect 4 Transcript Surface [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface only. The `az_games`
/ `az_sims` report-card knob assertion in `test/rl-canonicals/Main.hs`
closed on 2026-05-24 alongside Sprint `9.4`'s knob consumption. Real
network evaluation via the JIT engine for `runSearch` prior, live MinIO
self-play buffer round-trip, and live arena promotion migrated to Phase
`15` Sprint `15.9`.
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
- `src/JitML/RL/AlphaZero/Mcts.hs` declares `MctsConfig`, `MctsNode`,
  `MctsEdge`, `runSearch` (walking `mctsSimulations` rollouts), and
  `selectAction` (UCB with `cpuct`). Network-free mechanics tests use
  a neutral uniform default prior; production AlphaZero supplies a
  position-dependent `PriorOracle`.
- `JitML.RL.AlphaZero.Mcts.TranspositionTable`,
  `transpositionKey`, and `runSearchWithTable` cache canonical
  node-per-position entries so equivalent move sequences de-duplicate
  their search subtrees.
- `src/JitML/RL/AlphaZero/SelfPlay.hs` declares `SelfPlayConfig`,
  `SelfPlayBuffer`, `runSelfPlay` (drives
  `selfPlayGamesPerGeneration` games), and `bufferTranscriptHash` (the
  SHA-256 used as MinIO pointer suffix).
- The `SelfPlayBuffer` filesystem-backed `HasMinIO` round-trip is
  validated by `jitml-integration`; Phase 15 Sprint `15.9` closes the
  live `JitML.Service.MinIOSubprocess` self-play buffer round-trip.
- `src/JitML/RL/AlphaZero/PolicyValueNet.hs` owns the measured
  candidate-vs-reference arena win-rate helper used for promotion decisions;
  the dead standalone `Arena` module is deleted.
- Live MinIO checkpoint round-trip of the persistent self-play buffer is
  closed by Phase 15 Sprint `15.9` on top of the Phase 10 / Phase 4
  platform services.

### Validation

1. `selfPlayTranscript` is deterministic for a fixed seed.
2. `cabal test jitml-rl-canonicals` checks legal Connect 4 columns.
3. `jitml-unit` verifies the game catalog, network metadata, and arena
   win-rate helper.
4. Live validation: real `Mcts.hs` runs `az_sims` simulations
   per move; `SelfPlay.hs` plays `az_games` games per generation;
   `PolicyValueNet.hs` evaluates the new network against the previous best and
   the new champion is promoted only when the win rate exceeds the
   committed threshold; checkpoints round-trip the persistent self-play
   buffer bit-deterministically.

### Remaining Work

- The `rl-canonicals consumes cabal.project rl_steps and
  rl_eval_episodes knobs` case (Sprint `9.4`) also asserts the
  `az_games` and `az_sims` report-card knobs are populated from
  `cabal.project` (closed 2026-05-24).
- Wiring the `runSearch` prior into a real network evaluation via the JIT
  engine and validating the SelfPlayBuffer round-trip against live HTTP
  MinIO are owned by
  [phase-15-linux-cuda-and-cluster-closure.md](README.md#legacy-to-new-phase-map)
  Sprint `15.9`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

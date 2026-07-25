# Phase 116: No-Caveat RL, AlphaZero, and Tuning Runtime

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: No-Caveat RL, AlphaZero, and Tuning Runtime. Single-session phase migrated from legacy Sprint 9.12 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 116.1: No-Caveat RL, AlphaZero, and Tuning Runtime [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/RL/Algorithms/*`,
`src/JitML/RL/AlphaZero/*`, `src/JitML/Tune/*`, `src/JitML/App.hs`,
`test/rl-canonicals/Main.hs`, `test/hyperparameter/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`,
`documents/engineering/determinism_contract.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Make every RL, AlphaZero, and tuning workflow production-real rather than
partly validated through deterministic helper projections.

### Deliverables

- Every catalog algorithm (`PPO`, `A2C`, `TRPO`, `MaskablePPO`,
  `RecurrentPPO`, `DQN`, `QR-DQN`, `DDPG`, `TD3`, `SAC`, `CrossQ`, `TQC`,
  `ARS`, `HER`) has a train/eval/rollout path that uses its trained policy,
  checkpoint, replay state, and environment dynamics. Helper tests no longer
  derive synthetic policy/value/Q/quantile/actor inputs from reward lists.
- `jitml rl train`, `jitml rl eval`, `jitml rl rollout`, and `jitml rl
  alphazero self-play` persist checkpoint/replay artifacts that can be loaded by
  the CLI and the browser.
- AlphaZero has real terminal evaluators and winner/draw detection for Connect
  4, Othello, Hex, and Gomoku; arena win-rate no longer uses a "last placed
  piece wins" placeholder.
- AlphaZero game transcripts include enough state to drive interactive browser
  replay, MCTS visit-distribution inspection, engine analysis, and checkpoint
  comparison.
- Tuning objectives train the selected SL/RL workload through the selected
  substrate and scheduler/pruner state, persist full trial artifacts, and make
  promotion of a trial into a checkpointed run observable.
- Pending stand-in rows in the legacy ledger move to `Completed` only after
  runtime and test validation proves the replacement.

### Historical Validation

- Focused progress validation landed on 2026-06-14:
  `docker compose run --rm jitml cabal test jitml-rl-canonicals
  --test-options='--pattern=terminal' --test-show-details=direct` passed, and
  `docker compose run --rm jitml cabal test jitml-rl-canonicals
  --test-options='--pattern=loss' --test-show-details=direct` passed.
- Linux CPU validation passed on 2026-06-14 after the artifact/checkpoint
  closure:
  `docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`
  passed `29/29`, `docker compose run --rm jitml jitml test
  jitml-hyperparameter --linux-cpu` passed `16/16`, `docker compose run --rm
  jitml jitml test jitml-integration --linux-cpu` passed `71/71`, `docker
  compose run --rm jitml jitml check-code` returned `check-code: ok`, and
  `docker compose run --rm jitml jitml docs check` returned `docs check: ok`.
- Apple Silicon host validation passed on 2026-06-14:
  `cabal run jitml -- test jitml-rl-canonicals --apple-silicon` passed
  `29/29`, and `cabal run jitml -- test jitml-hyperparameter --apple-silicon`
  passed `16/16`.
- Linux CUDA validation passed on 2026-06-15 on a GPU-attached Docker host:
  `docker compose run --rm jitml-cuda jitml test jitml-rl-canonicals
  --linux-cuda` passed `29/29`, and `docker compose run --rm jitml-cuda jitml
  test jitml-hyperparameter --linux-cuda` passed `16/16`.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

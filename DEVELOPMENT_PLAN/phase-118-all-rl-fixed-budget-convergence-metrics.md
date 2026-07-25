# Phase 118: All-RL Fixed-Budget Convergence Metrics

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: All-RL Fixed-Budget Convergence Metrics. Single-session phase migrated from legacy Sprint 9.14 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 118.1: All-RL Fixed-Budget Convergence Metrics [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/RL/ConvergenceThresholds.hs`,
`src/JitML/RL/Algorithms/*.hs`, `src/JitML/RL/AlphaZero/*.hs`,
`test/rl-canonicals/Main.hs`
**Docs to update**: `../documents/engineering/training_metrics_and_splits.md`,
`../documents/engineering/training_workloads.md`,
`../documents/engineering/unit_testing_policy.md`, `system-components.md`

### Objective

Every advertised RL model has its own fixed budget and convergence metric. HER
and each AlphaZero game are required rows, not omissions or family-level
proxies. This sprint consumes the `TrainingBudget` / `CompletedTraining`
vocabulary introduced by Sprint `8.14`.

### Deliverables

- Add fixed-budget convergence rows for PPO, A2C, TRPO, MaskablePPO,
  RecurrentPPO, DQN, QR-DQN, DDPG, TD3, SAC, CrossQ, TQC, ARS, HER, and
  AlphaZero.
- Add HER's goal-conditioned convergence metric: goal success rate plus
  achieved-goal distance.
- Add per-game AlphaZero metrics for Connect 4, Othello, Hex, and Gomoku:
  arena win-rate, legal-move rate, and fixed MCTS simulation budget.
- Ensure every metric is emitted as checkpoint/TensorBoard-ready
  convergence statistics, not just an assertion local to the test.

### Validation

- `docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`
- `docker compose run --rm jitml jitml test jitml-integration --linux-cpu`
- `docker compose run --rm jitml jitml docs check`

### Current Validation State

- `docker compose run --rm jitml cabal test jitml-rl-canonicals --test-show-details=direct`
  passed **31 / 31**. The pure table now includes fixed-budget RL rows,
  `HER/goal-reaching` success-rate and achieved-goal-distance observations, and
  per-game AlphaZero rows for Connect 4, Othello, Hex, and Gomoku.
- `docker compose run --rm jitml cabal run jitml -- test jitml-rl-canonicals --linux-cpu`
  also passed through the project wrapper with **31 / 31** tests.
- `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  passed all **52** non-live integration cases before the expected **19** live
  failures caused by missing `.build/runtime/cluster-publication.json`.
- `docker compose run --rm jitml cabal run jitml -- docs check` passed
  (`docs check: ok`).
- `docker compose run --rm jitml cabal run jitml -- check-code` passed
  (`check-code: ok`).
- `docker compose run --rm jitml cabal test jitml-rl-canonicals --test-show-details=direct`
  passed **31 / 31** after the runtime `jitml rl train` worker began emitting
  fixed-budget completion metrics (`avg_reward`, `median_final_reward`,
  `env_steps`, `episode_count`, plus HER goal metrics when applicable) and a
  `CheckpointDoneRL` event carrying `CompletedTraining` for the written final
  checkpoint.
- `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  compiled the live daemon assertions for `median_final_reward` and
  `CheckpointDoneRL completed-training`, passed all **52** non-live cases, and
  failed only the expected **19** live cases because no bootstrapped cluster
  publication exists.
- `docker compose run --rm jitml cabal test jitml-rl-canonicals --test-show-details=direct`
  passed **31 / 31** after `jitml rl alphazero self-play` began writing
  checkpoint-ready `arena_win_rate`, `legal_move_rate`,
  `mcts_simulations_per_move`, and `self_play_samples` metrics and reusing the
  runtime completion publisher when executed under a worker run context.
- `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  was rerun after the AlphaZero runtime metric change; it again passed all
  **52** non-live cases and failed only the expected **19** no-cluster live
  cases.
- `./bootstrap/linux-cpu.sh up` completed the live `linux-cpu` rollout
  (**111** steps), and
  `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  passed **72 / 72** against that bootstrapped cluster after the RL collector
  was changed to observe `EpisodeDone`, `MetricUpdate median_final_reward`, and
  `CheckpointDoneRL completed-training` in a single Pulsar subscription pass.
  The live stanza also revalidated the existing AlphaZero self-play training
  plus `.jmw1` checkpoint round-trip through MinIO.
- `docker compose run --rm jitml cabal test jitml-rl-canonicals --test-show-details=direct`
  passed **31 / 31** after the live integration rerun.
- `docker compose run --rm jitml jitml test all --live --linux-cpu` passed the
  aggregate lane with **8 / 8** stanzas green. The `jitml-integration` live
  group observed the representative daemon-dispatched PPO/cartpole completion
  events and the `jitml-rl-canonicals` suite kept the all-RL/HER/AlphaZero
  convergence table at **31 / 31**.

### Remaining Work

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

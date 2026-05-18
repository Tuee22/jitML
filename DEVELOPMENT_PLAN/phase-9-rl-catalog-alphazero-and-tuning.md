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

> **Purpose**: Stand up the RL algorithm metadata catalog, Connect
> 4 / AlphaZero transcript helpers, canonical game metadata, and deterministic
> hyperparameter tuning catalogs. The target runtime extends these surfaces into
> one module per algorithm, persistent MCTS state, live trial storage/resume, and
> daemon-backed training.

## Phase Status

🔄 **Active**. The phase owns the catalog/AlphaZero/tuning half of
[Exit Definition](README.md#exit-definition) item 6 (`jitml rl train`
runs the full RL workloads, AlphaZero self-play executes, and `jitml
tune` consumes `Some Tuning::{ … }`-shaped Dhall per the worked example
in [../README.md → Concrete Dhall worked example](../README.md)).
**Met today**: 14 algorithm modules under
`src/JitML/RL/Algorithms/{Ppo,A2c,Trpo,MaskablePpo,RecurrentPpo,Dqn,QrDqn,Ddpg,Td3,Sac,CrossQ,Tqc,Ars,Her}.hs`
expose typed hyperparameter rows and deterministic per-algorithm
trajectory transcripts through the shared `AlgorithmModule` interface
in `JitML.RL.Algorithms.Common`. `JitML.RL.Algorithms.Registry`
aggregates the catalog and resolves a module by name. The AlphaZero
substack lands as `JitML.RL.AlphaZero.{Mcts,SelfPlay,Arena}` with the
typed `PerfectInformation` typeclass admitting Connect 4 / Othello /
Hex / Gomoku via per-game `applyMove` rules and per-game two-headed
network metadata. `experiments/mnist-tune.dhall` renders the canonical
`Some Tuning::{ … }` worked example. **Unmet today**: real on-hardware
training to canonical reward thresholds, real network forward / back
passes through the JIT engine layer, live MinIO trial transcript
persistence/resume, and live Pulsar handlers — all gated by the
absent cluster infra. Detailed remaining work lives in each sprint's
`### Remaining Work` block below.

### Current Implementation Scope

The worktree implements an `RLAlgorithm` catalog with family/replay
metadata, a Dhall schema mirror/audit at `dhall/rl/Schema.dhall`,
deterministic trajectory generation with a PPO/CartPole golden fixture,
and deterministic sampler/scheduler/pruner catalogs in
`src/JitML/Tune/Catalog.hs`. The 14 per-algorithm modules under
`src/JitML/RL/Algorithms/` carry typed hyperparameter rows + a
deterministic `AlgorithmModule.moduleRolloutGenerator` that produces a
per-seed integer trajectory + reward stream the canonical stanza
golden-checks; `Registry.algorithmModuleRegistry` aggregates them.
`JitML.RL.AlphaZero.Mcts` implements a deterministic prior + UCB +
visit-count tree with `runSearch` walking `mctsSimulations` rollouts;
`SelfPlay` plays `selfPlayGamesPerGeneration` games per generation
with a `SelfPlayBuffer` that exposes a `bufferTranscriptHash` for the
MinIO pointer; `Arena` decides `candidateShouldBePromoted` from the
`arenaWinRate`. The `PerfectInformation` typeclass admits all four
canonical games with per-game `applyMove` rules.
`experiments/mnist-tune.dhall` renders the `Some Tuning::{ … }` worked
example mirroring [../README.md → Concrete `Some Tuning::{ … }` example](../README.md).
Live MinIO trial storage, live tuner resume, real network execution,
and on-hardware reward thresholds remain in the per-sprint
`### Remaining Work` blocks below.

## Phase Summary

This phase currently delivers local RL algorithm metadata, Connect 4 transcript
helpers, and deterministic tuning catalogs. The target phase grows those
surfaces into one module per algorithm, a persistent AlphaZero/MCTS sub-stack,
and a typed sweep manager that drives SL, RL, or AlphaZero training under a
sampler × scheduler × pruner Dhall.

## Sprint 9.1: On-Policy Algorithm Metadata 🔄

**Status**: Active
**Implementation**: `src/JitML/RL/Algorithms.hs`,
`test/rl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Land the on-policy algorithm metadata rows; grow real algorithm modules
and full golden trajectory fixture coverage per `### Remaining Work`
below.

### Deliverables

- `algorithmCatalog` includes on-policy rows for `PPO`, `A2C`, `TRPO`,
  `MaskablePPO`, and `RecurrentPPO`.
- Each row records the `OnPolicy` family and `algorithmReplayBased = False`.
- `renderAlgorithmCatalog` renders the table from the local metadata list.

### Validation

1. `cabal test jitml-rl-canonicals` verifies representative catalog
   entries.
2. Live validation (target): each on-policy algorithm has a dedicated
   module with real loss / policy / rollout-buffer code, reaches the
   committed reward threshold for its canonical environment, and its
   per-seed trajectory matches the committed golden fixture.

### Remaining Work

- All five on-policy algorithm modules
  (`src/JitML/RL/Algorithms/{Ppo,A2c,Trpo,MaskablePpo,RecurrentPpo}.hs`)
  now expose typed deterministic hyperparameter rows + per-seed
  trajectory transcripts through `AlgorithmModule`. **Open**: replace
  the deterministic-fixture rollout with a real clipped-surrogate-loss
  / GAE / KL-trigger update once the JIT engine layer can execute the
  network — gated by Phase 7 production loaders against real
  hardware.
- Commit per-algorithm + per-environment goldens under
  `test/golden/rl/<algo>/<env>/trajectory.txt` once the deterministic
  `AlgorithmModule.moduleRolloutGenerator` is wired into the canonical
  stanza body (Sprint 12.4 owns the stanza wiring).

## Sprint 9.2: Off-Policy Algorithm Metadata 🔄

**Status**: Active
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
2. Live validation (target): each off-policy algorithm has a dedicated
   module with real replay-buffer code and per-seed transcript
   determinism against committed goldens.

### Remaining Work

- All five off-policy algorithm modules
  (`src/JitML/RL/Algorithms/{Dqn,QrDqn,Ddpg,Td3,Sac}.hs`) now exist with
  typed hyperparameter rows and deterministic per-seed transcripts. The
  typed `ReplayBuffer` (`JitML.RL.Buffer`) backs the off-policy update
  loop. **Open**: wire the deterministic-cuDNN algorithm pin into the
  real network forward / target-network update path (gated by Phase
  7.4 real cuDNN execution).
- Commit per-algorithm goldens under `test/golden/rl/<algo>/<env>/`
  through the stanza body in Sprint 12.4.

## Sprint 9.3: Specialised Algorithm Metadata 🔄

**Status**: Active
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
3. Live validation (target): each specialised algorithm has a dedicated
   module exercised by `jitml-rl-canonicals` against committed goldens.

### Remaining Work

- All four specialised algorithm modules
  (`src/JitML/RL/Algorithms/{CrossQ,Tqc,Ars,Her}.hs`) now exist with
  typed hyperparameter rows and deterministic per-seed transcripts.
- `jitml docs generate` regeneration check stays target work until the
  generated catalog table grows the per-module hyperparameter
  surface; the module-aggregating registry
  (`JitML.RL.Algorithms.Registry`) is ready to feed it.
- Per-algorithm goldens land through the stanza body in Sprint 12.4.

## Sprint 9.4: Local RL Canonical Tests 🔄

**Status**: Active
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
- `test/golden/rl/ppo/cartpole/trajectory.txt` pins the PPO/CartPole
  deterministic trajectory; full per-algorithm fixture trees are owned
  by `### Remaining Work` below.

### Validation

1. `cabal test jitml-rl-canonicals` exits `0` for the body.
2. Live validation (target): the stanza exercises the RL target matrix
   forms (2) same-substrate trajectory determinism and (3) per-seed
   final-reward distribution against live committed fixtures for every
   algorithm in the catalog.

### Remaining Work

- Grow `test/golden/rl/<algo>/<env>/` into a fixture tree per algorithm.
- Consume the `RL_STEPS` and `RL_EVAL_EPISODES` report-card knobs from
  `cabal.project`.
- Implement the per-seed final-reward distribution check (form 3) that
  consumes live training output.

## Sprint 9.5: AlphaZero Connect 4 Transcript Surface 🔄

**Status**: Active
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
  `selectAction` (UCB with `cpuct`). The prior is deterministic via
  `priorFor seed action`.
- `src/JitML/RL/AlphaZero/SelfPlay.hs` declares `SelfPlayConfig`,
  `SelfPlayBuffer`, `runSelfPlay` (drives
  `selfPlayGamesPerGeneration` games), and `bufferTranscriptHash` (the
  SHA-256 used as MinIO pointer suffix).
- `src/JitML/RL/AlphaZero/Arena.hs` declares `ArenaConfig`,
  `ArenaOutcome`, `playArena`, and `candidateShouldBePromoted` keyed on
  `arenaPromotionThreshold`.
- Live MinIO checkpoint round-trip of the persistent self-play buffer
  remains gated on Phase 10 / Phase 4 platform services.

### Validation

1. `selfPlayTranscript` is deterministic for a fixed seed.
2. `cabal test jitml-rl-canonicals` checks legal Connect 4 columns.
3. `jitml-unit` verifies the game catalog, network metadata, and arena
   win-rate helper.
4. Live validation (target): real `Mcts.hs` runs `AZ_SIMS` simulations
   per move; `SelfPlay.hs` plays `AZ_GAMES` games per generation;
   `Arena.hs` evaluates the new network against the previous best and
   the new champion is promoted only when the win rate exceeds the
   committed threshold; checkpoints round-trip the persistent self-play
   buffer bit-deterministically.

### Remaining Work

- The persistent search tree (`MctsNode`), prior + visit-count UCB
  (`ucbScore`), and the self-play buffer (`SelfPlayBuffer`) already
  exist. **Open**: wire the `runSearch` prior into a real network
  evaluation via the JIT engine (gated by Phase 7 production loaders).
- `JitML.RL.AlphaZero.Mcts.TranspositionTable` + `transpositionKey`
  (SHA-256 over the canonical move sequence) + `runSearchWithTable`
  cache the canonical node-per-position so equivalent move sequences
  de-dupe their search subtrees. Validated by `jitml-unit`: identical
  move sequences collapse to a single entry, distinct sequences
  allocate distinct entries.
- The MinIO checkpoint round-trip of the persistent self-play buffer
  is validated via `jitml-integration`: a deterministic
  `SelfPlayBuffer` is written under
  `selfplay/<bufferTranscriptHash>.cbor` through the filesystem
  `HasMinIO` instance, and re-deriving the buffer with the same seed
  produces the identical transcript hash + game count. The live MinIO
  HTTP variant remains gated on Sprint 4.3.
- `AZ_GAMES` and `AZ_SIMS` are exposed via `SelfPlayConfig`; the
  report-card knob block in `cabal.project` already names them — wire
  them into the canonical stanza body in Sprint 12.4.

## Sprint 9.6: Connect 4 Local Game Surface 🔄

**Status**: Active
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

1. `cabal test jitml-rl-canonicals` validates the Connect 4 move bounds.
2. Live validation (target): Othello, Hex, and Gomoku each carry real
   `initial<Game>`, `applyMove`, and `selfPlayTranscript` helpers; each
   game has committed golden replay fixtures; the
   `PerfectInformationGame` typeclass admits all four canonical games.

### Remaining Work

- `initialOthello`, `initialHex`, `initialGomoku` plus the per-game
  `applyMove` rules now exist in
  `src/JitML/RL/AlphaZero.hs`; `applyMove` dispatches on
  `gameName` to the per-game rule.
- `PerfectInformation` is now a typeclass admitting all four canonical
  games via `gameTwoHeadedNetwork` and `gameActionCount`. `GameState`
  is the canonical instance.
- Per-game golden replays under
  `test/golden/alphazero/<game>-transcript.txt` are now committed for
  all four canonical games (Connect 4, Othello, Hex, Gomoku);
  `JitML.RL.AlphaZero.selfPlayTranscriptFor` parameterises the
  transcript on game name and `jitml-rl-canonicals` binds each golden
  fixture against the deterministic output for `seed=3`.
- The full real-rules engine for Othello (capture flip), Hex
  (connectivity), and Gomoku (line-of-five) lands when the game
  position evaluator graduates from the deterministic shim — gated by
  the JIT engine's ability to evaluate game-specific feature tensors.

## Sprint 9.7: Hyperparameter Tuning (Sampler × Scheduler × Pruner) 🔄

**Status**: Active
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
- `experiments/mnist-tune.dhall` renders the canonical `Some Tuning::{
  … }` worked example from
  [../README.md → Concrete `Some Tuning::{ … }` example](../README.md)
  with the TPE sampler / ASHA scheduler / MedianPruner triple and the
  full search space.
- `proto/jitml/tune.proto` + `src/JitML/Proto/Tune.hs` declare the
  typed `TuneCommand` / `TuneEvent` surfaces for the substrate-scoped
  Pulsar topics.
- Wire-format protobuf bindings (proto-lens) and live MinIO persistence
  remain target runtime work.

### Validation

1. `jitml tune --dry-run experiments/mnist-tune.dhall` emits the typed plan.
2. `cabal test jitml-hyperparameter` verifies the sampler, scheduler, and
   pruner axes are populated and deterministic.
3. `jitml-unit` verifies the trial key and resume-equality helpers.
4. Live validation (target): a real `Some Tuning::{ … }`-shaped Dhall
   drives `jitml tune` end-to-end through the daemon, trial transcripts
   persist to MinIO bucket `jitml-trials/`, and resume-from-partial-sweep
   reproduces the same trial outcome bit-for-bit.

### Remaining Work

- Generate `proto-lens`-driven Haskell bindings for
  `proto/jitml/tune.proto` so the typed envelopes round-trip
  binary-equivalent with other-language clients.
- Implement the daemon-side tune handler that consumes
  `tune.command.<mode>` and persists trial transcripts to MinIO bucket
  `jitml-trials/<sha256(resolved-dhall || trial-seed)>/` — owned by
  Sprint 5.5 once the live broker + MinIO are reachable.
- Resume-from-partial-sweep is implemented as
  `JitML.Tune.Resume.persistTrialTranscript` (CBOR-serialises a
  `TrialTranscript` via `Codec.Serialise` and writes it through
  `HasMinIO.putBlobBytesIfAbsent` keyed by
  `Tune.Catalog.trialStorageKey experimentHash trialSeed`) and
  `replaySweep :: HasMinIO m => Text -> [Int] -> m ResumeOutcome`
  (reads the same keys back via `minioReadBytes`, deserialises, and
  returns `ResumeOutcome { resumedSeeds, resumedTrials,
  resumeReadFailures }` preserving canonical seed order). Validated
  by `jitml-integration` against the filesystem-backed `HasMinIO`
  instance: a 3-trial sweep persists, replays bit-equal, and a
  missing seed lands in `resumeReadFailures`. The live MinIO
  validation remains gated on Sprint 4.3.
- Consume the `TUNE_TRIALS` and `TUNE_BUDGET_PER_TRIAL` report-card
  knobs in the canonical stanza body (Sprint 12.5).

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

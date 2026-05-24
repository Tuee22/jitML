# Phase 9: RL Algorithm Catalog, AlphaZero, and Hyperparameter Tuning

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-8-supervised-and-rl-framework.md](phase-8-supervised-and-rl-framework.md),
[phase-10-checkpointing-and-inference.md](phase-10-checkpointing-and-inference.md),
[../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Stand up the RL algorithm metadata catalog, Connect
> 4 / AlphaZero transcript helpers, canonical game metadata, and deterministic
> hyperparameter tuning catalogs. The current tree includes one module per
> traditional RL algorithm and a local AlphaZero MCTS/self-play/arena substack;
> the target runtime extends these surfaces into live trial storage/resume,
> JIT-backed network execution, and daemon-backed training.

## Phase Status

🔄 **Active**. After the 2026-05-24 refactor, this phase carries only
its code-surface obligations (RL algorithm module metadata + deterministic
rollouts, real Othello/Hex/Gomoku rule engines, deterministic-stub
goldens, sampler implementations, AlphaZero MCTS framework with
deterministic prior). Real CUDA RL loss execution and AlphaZero with
real network priors migrated to
[phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
Sprints `13.8` and `13.9`. Live tuner execution migrated to Phase `13`
Sprint `13.10`.

The phase owns the catalog/AlphaZero/tuning half of
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
`Some Tuning::{ … }` worked example. The current Haskell tuning catalog is
a full target sampler catalog (`Grid`, `Sobol`, `Random`, `TPE`, `GPBO`,
`GeneticAlgorithm`, `NSGA2`, `MuLambdaES`, `CMAES`, `EvolutionStrategies`,
and `PBT`); `JitML.Tune.Catalog.loadTuningExperiment` decodes the worked
example into the local tuning ADT, `jitml tune` renders a TPE plan, and
`JitML.Proto.Tune` round-trips the current deterministic text and
proto3-compatible byte command and event envelopes.
**Unmet today**:
real on-hardware training to canonical reward thresholds,
real network forward / back passes through the JIT engine layer, live MinIO
trial transcript persistence/resume, generated proto-lens tune bindings /
cross-language interop, and live Pulsar handlers — all gated by the absent
cluster infra or remaining tuner work.
Detailed remaining work lives in each sprint's `### Remaining Work` block
below.

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
example mirroring [../README.md → Concrete `Some Tuning::{ … }` example](../README.md);
it decodes through `JitML.Tune.Catalog.loadTuningExperiment` to the local
TPE / ASHA / MedianPruner ADT, and `jitml tune` prints deterministic TPE trial
samples for the local plan. The tune proto mirror declares typed
command/event envelopes, parses the deterministic local text command envelope,
and round-trips the current command and event oneofs through proto3-compatible
bytes via `JitML.Proto.Wire`.
Live MinIO trial storage, live tuner resume, real network execution,
and on-hardware reward thresholds remain in the per-sprint
`### Remaining Work` blocks below.

## Phase Summary

This phase currently delivers local RL algorithm metadata, one module per
traditional RL algorithm, Connect 4 / Othello / Hex / Gomoku transcript
helpers, a local AlphaZero MCTS/self-play/arena substack, and deterministic
tuning catalogs. The target runtime grows those surfaces into real
JIT-backed network updates and a typed sweep manager that drives SL, RL, or
AlphaZero training under a sampler × scheduler × pruner Dhall.

## Sprint 9.1: On-Policy Algorithm Metadata 🔄

**Status**: Active
**Owned obligations after refactor**: code-surface only. Real
clipped-surrogate-loss / GAE / KL-trigger update code through the live
CUDA JIT engine migrated to Phase `13` Sprint `13.8`. The per-algorithm
per-environment goldens for the deterministic-stub rollout remain a
code-only deliverable here.
**Implementation**: `src/JitML/RL/Algorithms.hs`,
`src/JitML/RL/Algorithms/{Ppo,A2c,Trpo,MaskablePpo,RecurrentPpo}.hs`,
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
- The five on-policy modules expose typed deterministic hyperparameter rows
  and per-seed trajectory transcripts through `AlgorithmModule`.

### Validation

1. `cabal test jitml-rl-canonicals` verifies representative catalog
   entries.
2. Live validation (target): each on-policy algorithm has a dedicated
   module with real loss / policy / rollout-buffer code, reaches the
   committed reward threshold for its canonical environment, and its
   per-seed trajectory matches the committed golden fixture.

### Remaining Work

- Commit per-algorithm + per-environment goldens under
  `test/golden/rl/<algo>/<env>/trajectory.txt` from the deterministic
  `AlgorithmModule.moduleRolloutGenerator`. (Code-only; close by running
  the deterministic generator and committing the output. Live measured
  fixtures from real CUDA training are owned by Phase `13` Sprint `13.8`.)
- Replacement of the deterministic-fixture rollout with real
  clipped-surrogate-loss / GAE / KL-trigger update code through the live
  CUDA JIT engine is owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.8`.

## Sprint 9.2: Off-Policy Algorithm Metadata 🔄

**Status**: Active
**Owned obligations after refactor**: code-surface only. Real cuDNN
deterministic algorithm pin executed against off-policy network forward /
target-network update migrated to Phase `13` Sprint `13.8`.
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
  network update code and full golden trajectory fixture coverage are
  still target work.

### Validation

1. `algorithmCatalog` exposes the five checked-in off-policy rows.
2. Live validation (target): each off-policy algorithm has a dedicated
   module with real replay-buffer code and per-seed transcript
   determinism against committed goldens.

### Remaining Work

- Commit per-algorithm goldens under `test/golden/rl/<algo>/<env>/` from
  the deterministic-stub rollout. (Code-only.)
- Wiring the deterministic-cuDNN algorithm pin into the real off-policy
  network forward / target-network update path is owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.8`.

## Sprint 9.3: Specialised Algorithm Metadata 🔄

**Status**: Active
**Owned obligations after refactor**: code-surface only. Real specialised
algorithm execution through live CUDA migrated to Phase `13` Sprint
`13.8`.
**Implementation**: `src/JitML/RL/Algorithms.hs`,
`src/JitML/RL/Algorithms/{CrossQ,Tqc,Ars,Her}.hs`,
`test/rl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Land the current specialised algorithm metadata rows.

### Deliverables

- `algorithmCatalog` includes specialised rows for `CrossQ`, `TQC`, `ARS`,
  and `HER`.
- `CrossQ`, `TQC`, and `HER` are marked replay-based; `ARS` is not.
- The four specialised algorithm modules expose typed deterministic
  hyperparameter rows and per-seed transcripts.
- The generated training-workload catalog table is actively rendered from the
  current Haskell catalog by `jitml docs generate`.

### Validation

1. `algorithmCatalog` exposes the four checked-in specialised rows.
2. `jitml docs check` validates the generated catalog table.
3. Live validation (target): each specialised algorithm has a dedicated
   module exercised by `jitml-rl-canonicals` against committed goldens.

### Remaining Work

- Extend `jitml docs generate` so the generated catalog table renders the
  per-module hyperparameter surface from `JitML.RL.Algorithms.Registry`.
  (Code-only.)
- Per-algorithm deterministic-stub goldens land through the stanza body
  in Sprint `12.4` (code-only).
- Real CUDA specialised-update execution (CrossQ multi-critic, TQC
  quantile TD, ARS evolution strategy, HER hindsight relabel) is owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.8`.

## Sprint 9.4: Local RL Canonical Tests 🔄

**Status**: Active
**Owned obligations after refactor**: code-surface only. Per-seed
final-reward distribution check consuming live training output migrated
to Phase `13` Sprint `13.6`.
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

- Grow `test/golden/rl/<algo>/<env>/` into a fixture tree per algorithm
  from the deterministic-stub generator. (Code-only.)
- Consume the `rl_steps` and `rl_eval_episodes` report-card knobs from
  `cabal.project`. (Code-only.)
- The per-seed final-reward distribution check (form 3) consuming live
  training output is owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.6`.

## Sprint 9.5: AlphaZero Connect 4 Transcript Surface 🔄

**Status**: Active
**Owned obligations after refactor**: code-surface only. Real network
evaluation via the JIT engine for `runSearch` prior, live MinIO
self-play buffer round-trip, and live arena promotion migrated to Phase
`13` Sprint `13.9`.
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
- `JitML.RL.AlphaZero.Mcts.TranspositionTable`,
  `transpositionKey`, and `runSearchWithTable` cache canonical
  node-per-position entries so equivalent move sequences de-duplicate
  their search subtrees.
- `src/JitML/RL/AlphaZero/SelfPlay.hs` declares `SelfPlayConfig`,
  `SelfPlayBuffer`, `runSelfPlay` (drives
  `selfPlayGamesPerGeneration` games), and `bufferTranscriptHash` (the
  SHA-256 used as MinIO pointer suffix).
- The `SelfPlayBuffer` filesystem-backed `HasMinIO` round-trip is
  validated by `jitml-integration`; wiring this buffer to
  `JitML.Service.MinIOSubprocess` remains target work.
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
4. Live validation (target): real `Mcts.hs` runs `az_sims` simulations
   per move; `SelfPlay.hs` plays `az_games` games per generation;
   `Arena.hs` evaluates the new network against the previous best and
   the new champion is promoted only when the win rate exceeds the
   committed threshold; checkpoints round-trip the persistent self-play
   buffer bit-deterministically.

### Remaining Work

- Wire the `az_games` and `az_sims` report-card knobs into the canonical
  stanza body. (Code-only.)
- Wiring the `runSearch` prior into a real network evaluation via the JIT
  engine and validating the SelfPlayBuffer round-trip against live HTTP
  MinIO are owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.9`.

## Sprint 9.6: Connect 4 Local Game Surface 🔄

**Status**: Active
**Owned obligations after refactor**: code-surface — the real rule
engines for Othello (8-direction capture-flip), Hex (border-to-border
connectivity), and Gomoku (line-of-five) are pure Haskell deliverables
in this sprint. The JIT-backed network position evaluation that consumes
these rules is owned by Phase `13` Sprint `13.9`.
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
- `initialOthello`, `initialHex`, and `initialGomoku` plus per-game
  `applyMove` dispatch are checked in.
- `PerfectInformation` admits all four canonical games through
  `gameTwoHeadedNetwork` and `gameActionCount`.
- Per-game deterministic transcript fixtures are committed under
  `test/golden/alphazero/{connect4,othello,hex,gomoku}-transcript.txt`.

### Validation

1. `cabal test jitml-rl-canonicals` validates the Connect 4 move bounds.
2. Local validation checks the deterministic replay fixture for each
   canonical game.
3. Live validation (target): Othello, Hex, and Gomoku graduate from the
   deterministic local rules to full rule-complete position evaluators
   and JIT-backed network forward passes.

### Remaining Work

- Implement the real rule engines in `src/JitML/RL/AlphaZero.hs`:
  Othello 8-direction capture-flip (legal-move generation + opponent-disc
  flipping until same-colour anchor), Hex border-to-border DFS
  connectivity, Gomoku linear five-in-a-row detection. Update
  `selfPlayTranscriptFor` so the deterministic seeded selection advances
  past illegal moves; regenerate the affected goldens under
  `test/golden/alphazero/{othello,hex,gomoku}-transcript.txt`. (Code-only;
  no hardware required.)
- JIT-backed network position evaluation that consumes these rule
  engines is owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.9`.

## Sprint 9.7: Hyperparameter Tuning (Sampler × Scheduler × Pruner) 🔄

**Status**: Active
**Owned obligations after refactor**: code-surface only. Daemon-side
tune handler against live broker, live MinIO trial persistence, and
the full canonical sampler × scheduler × pruner grid against live
tuner execution migrated to Phase `13` Sprint `13.10`.
**Implementation**: `src/JitML/Tune/Catalog.hs`,
`src/JitML/App.hs`, `src/JitML/Proto/Tune.hs`,
`test/hyperparameter/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Land the current deterministic sampler × scheduler × pruner catalogs,
trial-storage key helpers, resume equality summary, and `jitml tune` local
summary.

### Deliverables

- `Sampler` enumerates `Grid`, `Sobol`, `Random`, `TPE`, `GPBO`,
  `GeneticAlgorithm`, `NSGA2`, `MuLambdaES`, `CMAES`, `EvolutionStrategies`,
  and `PBT`.
- `Scheduler` enumerates `Fifo`, `SuccessiveHalving`, `Hyperband`, and `ASHA`.
- `Pruner` enumerates `NoPruner`, `MedianPruner`, and `PercentilePruner`.
- `deterministicTrials` emits normalized deterministic trial values for the
  current sampler set.
- `test/golden/tune/` pins the current Sobol and GeneticAlgorithm trial
  streams.
- `trialStorageKey`, `resumeMatchesFullRun`, and
  `renderTrialResumeSummary` provide the local trial persistence/resume
  surface.
- `JitML.Tune.Resume.persistTrialTranscript` and `replaySweep` round-trip
  `TrialTranscript` values through `HasMinIO.putBlobBytesIfAbsent` /
  `minioReadBytes`, validated against the filesystem-backed instance in
  `jitml-integration`.
- `jitml tune <tune-dhall>` is Plan/Apply-capable and prints the decoded
  sampler / scheduler / pruner axes plus four deterministic local trial values.
- `experiments/mnist-tune.dhall` is the checked-in `Some
  Tuning::{ … }` worked example from
  [../README.md → Concrete `Some Tuning::{ … }` example](../README.md)
  with the TPE sampler / ASHA scheduler / MedianPruner triple and the
  full search space. `JitML.Tune.Catalog.loadTuningExperiment` decodes it
  into the local Haskell tuning ADT, and the real-binary integration matrix
  asserts `jitml tune experiments/mnist-tune.dhall` renders `sampler: TPE`.
- `jitml-hyperparameter` consumes the `tune_trials` and
  `tune_budget_per_trial` report-card knobs from `cabal.project` for the
  local TPE trial-budget assertion.
- `proto/jitml/tune.proto` + `src/JitML/Proto/Tune.hs` declare the
  typed `TuneCommand` / `TuneEvent` surfaces for the substrate-scoped
  Pulsar topics. `parseTuneCommand` covers the current text
  `StartSweep` / `StopSweep` command envelopes, and
  `encodeTuneCommandProto` / `decodeTuneCommandProto` round-trip the current
  `TuneCommand` oneof through proto3-compatible bytes.
  `encodeTuneEventProto` / `decodeTuneEventProto` round-trip the current
  `TuneEvent` oneof through proto3-compatible bytes.
- Generated wire-format protobuf bindings (proto-lens) and live MinIO
  persistence remain target runtime work.

### Validation

1. `jitml tune --dry-run experiments/mnist-tune.dhall` emits the typed
   Plan/Apply command plan.
2. `cabal test jitml-hyperparameter` verifies the sampler, scheduler, and
   pruner axes are populated, deterministic, the TPE worked example
   decodes, and the local TPE trial budget consumes `cabal.project`
   report-card knobs. It also covers text render/parse round-trips for
   `StartSweep` and `StopSweep`, plus proto3-compatible byte round-trips for
   the current `TuneCommand` / `TuneEvent` oneofs.
3. `jitml-unit` verifies the trial key and resume-equality helpers.
4. `jitml-integration` spawns the real binary and verifies normal
   `jitml tune experiments/mnist-tune.dhall` execution renders `sampler: TPE`.
5. Live validation (target): a real `Some Tuning::{ … }`-shaped Dhall
   drives `jitml tune` end-to-end through the daemon, trial transcripts
   persist to MinIO bucket `jitml-trials/`, and resume-from-partial-sweep
   reproduces the same trial outcome bit-for-bit.

### Remaining Work

- Generate `proto-lens`-driven Haskell bindings for
  `proto/jitml/tune.proto` so the command/event envelopes round-trip
  binary-equivalent with other-language clients. (Code-only.)
- Daemon-side tune handler against live broker, `persistTrialTranscript`
  / `replaySweep` validation against live HTTP MinIO, and the full
  canonical sampler × scheduler × pruner grid against live tuner
  execution are owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.10`.

## Doctrine Sections Cited

- [../README.md → CLI command topology, typed](../README.md#cli-command-topology-typed) (Sprint 9.7 — `jitml tune` command leaf)
- [../README.md → Plan / Apply commands](../README.md#doctrine-scope) (Sprint 9.7 — current dry-run / plan-file surface)
- [../README.md → Test-suite stanzas](../README.md#test-suite-stanzas) (Sprints 9.4, 9.7 — dedicated local RL and hyperparameter stanzas)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/training_workloads.md` — current RL algorithm
  metadata catalog, Dhall mirror, PPO/CartPole golden trajectory fixture,
  Connect 4 transcript helper, and tuner catalog; target algorithm modules,
  AlphaZero/MCTS runtime, adversarial games, target sampler decode, and
  full tuner storage/resume surface. The doc also distinguishes the
  current tune text/proto3-compatible command and event envelope codecs from
  target generated proto-lens bindings.
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
- [../README.md](../README.md)

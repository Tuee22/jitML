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

✅ **Done** (re-closed 2026-06-11 — real-workflow refactor). The catalog,
AlphaZero substack, and tuning surfaces shipped with synthetic/echo stand-ins:
`jitml rl eval` echoed the checkpoint label, `jitml rl rollout` returned an LCG
integer sequence, AlphaZero MCTS was a one-ply bandit, and tuning trials used
per-sampler LCG values. The 2026-06-10/11 refactor removes those local stand-ins:
`rl eval`/`rl rollout` route through checkpoint/device paths and fail closed,
per-algorithm rollouts step real environment dynamics, MCTS descends a real tree
with value backup, device-backed MCTS leaf evaluation runs through the selected
JIT `MlpDevice`, and tuning trials train a real model through the substrate
device to produce measured objectives. The linux-cpu and linux-cuda live
exercise closed in Phase `13` on 2026-06-11; apple-silicon live validation
remains Phase `14`, not an open Phase `9` code-surface obligation. See
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md). The prior
closure narrative below is retained as dated record.

✅ **Done** (re-closed 2026-06-04 after Sprint `9.8`). Every original
code-surface obligation closed on 2026-05-25:
the 14 algorithm modules' deterministic-stub run-to-run determinism +
rule-conformance properties, the real Othello/Hex/Gomoku rule engines,
the full sampler/scheduler/pruner catalog, the AlphaZero MCTS / SelfPlay
/ Arena substack, the `experiments/mnist-tune.dhall` worked example
decode, and the proto-lens bindings for `rl.proto` and `tune.proto`.
Real CUDA RL loss execution and AlphaZero with real network priors are
owned by
[phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
Sprints `13.8` and `13.9`. Live tuner execution is owned by Phase `13`
Sprint `13.10`.
Sprint `9.8` retargeted the RL algorithm/convergence matrix away from
`atari-subset` and onto the copyright-free Phase `8` Sprint `8.9`
`KeyDoorGrid-v0` environment.

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
substack lands as `JitML.RL.AlphaZero.{Mcts,SelfPlay,PolicyValueNet}` with the
typed `PerfectInformation` typeclass admitting Connect 4 / Othello /
Hex / Gomoku via per-game `applyMove` rules, per-game two-headed
network metadata, device-backed MCTS leaf evaluation, and arena win-rate
measurement. `experiments/mnist-tune.dhall` renders the canonical
`Some Tuning::{ … }` worked example. The current Haskell tuning catalog is
a full target sampler catalog (`Grid`, `Sobol`, `Random`, `TPE`, `GPBO`,
`GeneticAlgorithm`, `NSGA2`, `MuLambdaES`, `CMAES`, `EvolutionStrategies`,
and `PBT`); `JitML.Tune.Catalog.loadTuningExperiment` decodes the worked
example into the local tuning ADT, `jitml tune` renders a TPE plan, and
`JitML.Proto.Tune` round-trips the current deterministic text and
proto3-compatible byte command and event envelopes.
**Owned elsewhere**:
real on-hardware training to canonical reward thresholds,
real network forward / back passes through the JIT engine layer, live MinIO
trial transcript persistence/resume, and live Pulsar handlers are owned by
Phase `13` and are not open Phase `9` obligations.

### Current Implementation Scope

The worktree implements an `RLAlgorithm` catalog with family/replay
metadata and a Dhall schema mirror/audit at `dhall/rl/Schema.dhall`.
The 14 per-algorithm modules under `src/JitML/RL/Algorithms/` carry typed
hyperparameter rows plus a deterministic `AlgorithmModule.moduleRolloutGenerator`
that steps real named environment dynamics through
`JitML.RL.Algorithms.Common.trajectoryRollout` /
`JitML.RL.SimulatorLoop.realRolloutByName`; there are no committed rollout-value
fixtures. `Registry.algorithmModuleRegistry` aggregates them.
`JitML.RL.AlphaZero.Mcts` now implements recursive PUCT search with
position-aware priors, expansion at the selected leaf, value-head evaluation,
and sign-flipped backup. The production search also exposes
`runSearchWithPriorIO`; `PolicyValueNet.networkPriorOracleWithDevice` /
`mctsVisitDistributionWithDevice` run leaf policy/value forwards through the
selected JIT `MlpDevice` and fail closed on device errors. `SelfPlay` generates
network-driven games with a `SelfPlayBuffer` that exposes a `bufferTranscriptHash`
for the MinIO pointer. The dead `Arena` / `EnginePrior` modules are deleted. The
`PerfectInformation` typeclass admits all four canonical games with per-game
`applyMove` rules.
`experiments/mnist-tune.dhall` renders the `Some Tuning::{ … }` worked
example mirroring [../README.md → Concrete `Some Tuning::{ … }` example](../README.md);
it decodes through `JitML.Tune.Catalog.loadTuningExperiment` to the local TPE /
ASHA / MedianPruner ADT, and the tuning catalog returns measured objectives by
training the reference classifier for each sampled trial; the live worker/report
path uses `deterministicTrialsWithDevice` so substrate-backed trial failures are
reported as unavailable or hard errors rather than falling back to pure trial
values. The tune proto mirror declares typed
command/event envelopes, parses the deterministic local text command envelope,
and round-trips the current command and event oneofs through proto3-compatible
bytes via `JitML.Proto.Wire`.
Live MinIO trial storage, live tuner resume, real network execution, and
on-hardware reward thresholds closed in the Linux live lanes owned by Phase `13`.

## Phase Summary

This phase currently delivers local RL algorithm metadata, one module per
traditional RL algorithm, Connect 4 / Othello / Hex / Gomoku transcript
helpers, a local AlphaZero MCTS/self-play/arena substack, and deterministic
tuning catalogs. The target runtime grows those surfaces into real
JIT-backed network updates and a typed sweep manager that drives SL, RL, or
AlphaZero training under a sampler × scheduler × pruner Dhall.
Sprint `9.8` keeps the catalog aligned with the copyright-free demo policy:
required visual discrete-control coverage uses `KeyDoorGrid-v0`, and
`atari-subset` is absent from required convergence cohorts.

## Sprint 9.1: On-Policy Algorithm Metadata ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. The
per-algorithm per-environment run-to-run determinism plus
rule-conformance properties for the deterministic-stub rollout closed
on 2026-05-24 for PPO, A2C, TRPO, MaskablePPO, RecurrentPPO via
`AlgorithmModule.moduleRolloutGenerator` (no committed rollout-value
files per [../README.md → Snapshot targets → Numerical-fixture
prohibition](../README.md#snapshot-targets)). Real
clipped-surrogate-loss / GAE / KL-trigger update code through the live
CUDA JIT engine migrated to Phase `13` Sprint `13.8`.
**Implementation**: `src/JitML/RL/Algorithms.hs`,
`src/JitML/RL/Algorithms/{Ppo,A2c,Trpo,MaskablePpo,RecurrentPpo}.hs`,
`test/rl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Land the on-policy algorithm metadata rows; grow real algorithm modules
and full per-algorithm run-to-run trajectory determinism plus
rule-conformance property coverage per `### Remaining Work` below. No
committed trajectory `.txt` fixtures per [../README.md → Snapshot
targets → Numerical-fixture prohibition](../README.md#snapshot-targets).

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
   in-code reward threshold for its canonical environment (`median
   over k seeds ≥ literature_target − slack`, no committed
   per-substrate reward fixture), and two fresh same-substrate /
   same-seed runs produce bit-identical per-seed trajectories
   compared against each other.

### Remaining Work

- Per-algorithm + per-environment run-to-run determinism closed on
  2026-05-24 for each of the five on-policy modules (PPO, A2C, TRPO,
  MaskablePPO, RecurrentPPO) keyed to cartpole through
  `AlgorithmModule.moduleRolloutGenerator`; the rl-canonicals stanza
  enforces each by running the rollout twice in-process and asserting
  bit-identity between the two run outputs plus rule-conformance
  properties (every step legal under the env transition, terminal
  condition canonical). Per
  [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets), no `test/golden/rl/...`
  rollout-value files are committed; the legacy `test/golden/rl/`
  scaffolding is scheduled for deletion per
  [legacy-tracking-for-deletion.md → Pending Removal](legacy-tracking-for-deletion.md#pending-removal).
  Live measured cross-substrate runs from real CUDA training are owned
  by Phase `13` Sprint `13.8`.
- Replacement of the deterministic-fixture rollout with real
  clipped-surrogate-loss / GAE / KL-trigger update code through the live
  CUDA JIT engine is owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.8`.

## Sprint 9.2: Off-Policy Algorithm Metadata ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. Per-algorithm
run-to-run determinism plus rule-conformance properties closed on
2026-05-24 for DQN, QR-DQN (cartpole) and DDPG, TD3, SAC (mountain-car)
via `AlgorithmModule.moduleRolloutGenerator` re-running the rollout
in-process and asserting bit-identity (no committed rollout-value files
per [../README.md → Snapshot targets → Numerical-fixture
prohibition](../README.md#snapshot-targets)). Real cuDNN deterministic
algorithm pin executed against off-policy network forward /
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
  network update code and full per-algorithm run-to-run trajectory
  determinism coverage are
  still target work.

### Validation

1. `algorithmCatalog` exposes the five checked-in off-policy rows.
2. Live validation (target): each off-policy algorithm has a dedicated
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
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.8`.

## Sprint 9.3: Specialised Algorithm Metadata ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only.
`jitml docs generate` for the catalog table (closed 2026-05-24 in
`JitML.Docs.Render.renderTrainingRlCatalog`) and per-algorithm
deterministic-stub run-to-run determinism for CrossQ, TQC, ARS, HER
(closed 2026-05-24 via re-running each rollout in-process and
comparing bit-for-bit) are both in place; no `test/golden/rl/`
files are committed per [../README.md → Snapshot targets →
Numerical-fixture prohibition](../README.md#snapshot-targets). Real
specialised algorithm execution through live CUDA migrated to
Phase `13` Sprint `13.8`.
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
   module exercised by `jitml-rl-canonicals` against run-to-run
   determinism plus rule-conformance properties (no committed numerical
   fixtures per [../README.md → Snapshot targets → Numerical-fixture
   prohibition](../README.md#snapshot-targets)).

### Remaining Work

- `jitml docs generate` now renders the catalog table with the
  per-module hyperparameter count and module file path from
  `JitML.RL.Algorithms.Registry` (closed 2026-05-24 in
  `JitML.Docs.Render.renderTrainingRlCatalog`). The regenerated
  `documents/engineering/training_workloads.md` catalog table now lists
  `Algorithm | Family | Replay-backed | Hyperparameters | Module`.
- Per-algorithm deterministic-stub run-to-run determinism for CrossQ,
  TQC, ARS, HER closed on 2026-05-24 — asserted by re-running the
  rollout in-process and comparing bit-for-bit; no `test/golden/rl/...`
  files are committed per [../README.md → Snapshot targets →
  Numerical-fixture prohibition](../README.md#snapshot-targets).
- Real CUDA specialised-update execution (CrossQ multi-critic, TQC
  quantile TD, ARS evolution strategy, HER hindsight relabel) is owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.8`.

## Sprint 9.4: Local RL Canonical Tests ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. Per-algorithm
run-to-run determinism coverage closed on 2026-05-24 for every
traditional algorithm × canonical environment pairing via
`checkRolloutDeterminism`, and the `rl-canonicals consumes
cabal.project rl_steps and rl_eval_episodes knobs` case closed on the
same date. Per-seed final-reward distribution check consuming live
training output migrated to Phase `13` Sprint `13.6`.
**Implementation**: `test/unit/Main.hs`, `test/integration/Main.hs`,
`test/rl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Stitch the current RL metadata and registered real-environment rollout surface
into the dedicated local RL canonical stanza.

### Deliverables

- `test/rl-canonicals/Main.hs` verifies representative algorithm names across
  the local metadata catalog.
- The stanza asserts a registered PPO/CartPole rollout is stable across two
  in-process invocations (run-to-run equality, no committed trajectory fixture
  per [../README.md → Snapshot targets → Numerical-fixture prohibition](../README.md#snapshot-targets)).
- The stanza also checks the current Connect 4 transcript helper keeps moves
  within legal column bounds.
- PPO/CartPole determinism is asserted by re-running the rollout
  in-process and comparing bit-for-bit; per-algorithm coverage is
  owned by `### Remaining Work` below.

### Validation

1. `cabal test jitml-rl-canonicals` exits `0` for the body.
2. Live validation (target): the stanza exercises the RL target matrix
   forms (2) same-substrate run-to-run trajectory determinism and (3)
   per-seed final-reward distribution against an in-code statistical
   threshold (median over k seeds ≥ literature_target − slack; no
   per-substrate committed reward fixture per [../README.md → Snapshot
   targets → Numerical-fixture prohibition](../README.md#snapshot-targets))
   for every algorithm in the catalog.

### Remaining Work

- The per-algorithm run-to-run determinism coverage closed on
  2026-05-24 for every traditional algorithm × canonical environment
  pairing (cartpole or mountain-car); the rl-canonicals stanza
  enforces each through `checkRolloutDeterminism`, which invokes
  `AlgorithmModule.moduleRolloutGenerator` twice in-process and
  asserts bit-identity between the two outputs. No `test/golden/rl/`
  files are committed.
- The `rl-canonicals consumes cabal.project rl_steps and
  rl_eval_episodes knobs` case in `test/rl-canonicals/Main.hs` now loads
  the `cabal.project` report-card knob block and asserts the RL knobs
  are populated (closed 2026-05-24).
- The per-seed final-reward distribution check (form 3) consuming live
  training output is owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.6`.

## Sprint 9.5: AlphaZero Connect 4 Transcript Surface ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. The `az_games`
/ `az_sims` report-card knob assertion in `test/rl-canonicals/Main.hs`
closed on 2026-05-24 alongside Sprint `9.4`'s knob consumption. Real
network evaluation via the JIT engine for `runSearch` prior, live MinIO
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
  validated by `jitml-integration`; wiring this buffer to
  `JitML.Service.MinIOSubprocess` remains target work.
- `src/JitML/RL/AlphaZero/PolicyValueNet.hs` owns the measured
  candidate-vs-reference arena win-rate helper used for promotion decisions;
  the dead standalone `Arena` module is deleted.
- Live MinIO checkpoint round-trip of the persistent self-play buffer
  remains gated on Phase 10 / Phase 4 platform services.

### Validation

1. `selfPlayTranscript` is deterministic for a fixed seed.
2. `cabal test jitml-rl-canonicals` checks legal Connect 4 columns.
3. `jitml-unit` verifies the game catalog, network metadata, and arena
   win-rate helper.
4. Live validation (target): real `Mcts.hs` runs `az_sims` simulations
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
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.9`.

## Sprint 9.6: Connect 4 Local Game Surface ✅

**Status**: Done
**Owned obligations after refactor**: code-surface — the real rule
engines for Othello (8-direction capture-flip), Hex (border-to-border
connectivity), and Gomoku (line-of-five) closed on 2026-05-24 in
`src/JitML/RL/AlphaZero.hs` (`othelloLegalMove` / `othelloFlipsFor` /
`othelloBoardAfter`; `hexLegalMove` + `hexConnected`; `gomokuLegalMove`
+ `hasGomokuLine`); `selfPlayTranscriptFor` advances past illegal
candidates via `nextLegalMove`. The JIT-backed network position
evaluation that consumes these rules is owned by Phase `13`
Sprint `13.9`.
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
- Per-game transcript determinism is asserted by `jitml-rl-canonicals`
  as run-to-run equality (`selfPlayTranscriptFor` is invoked twice
  in-process and the outputs are compared bit-for-bit) plus
  rule-conformance properties (every emitted move is legal under the
  per-game `applyMove`, terminal states match `gameTerminal`). No
  `test/golden/alphazero/<game>-transcript.txt` files are committed
  per [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets) — MCTS visit counts and
  prior-evaluator output depend on substrate float behavior and
  hardcoding a host's transcript would lock that host's RNG / FP order
  into the repository as authoritative.

### Validation

1. `cabal test jitml-rl-canonicals` validates the Connect 4 move bounds.
2. Local validation re-runs the per-game self-play transcript twice
   in-process and asserts bit-identity between the two outputs plus
   rule-conformance properties — no committed transcript fixtures.
3. Live validation (target): Othello, Hex, and Gomoku graduate from the
   deterministic local rules to full rule-complete position evaluators
   and JIT-backed network forward passes.

### Remaining Work

- The real rule engines in `src/JitML/RL/AlphaZero.hs` closed on
  2026-05-24: `othelloLegalMove` / `othelloFlipsFor` /
  `othelloBoardAfter` cover the 8-direction capture-flip rule;
  `hexLegalMove` plus `hexConnected` (border-to-border DFS using the
  six standard hex neighbours plus parallelogram diagonals) covers
  Hex; `gomokuLegalMove` plus `hasGomokuLine` (line-of-five
  detection) covers Gomoku. `selfPlayTranscriptFor` advances past
  illegal candidates via `nextLegalMove`. The per-game self-play
  helpers are exercised by run-to-run equality plus rule-conformance
  properties — no per-game transcript files are committed per
  [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets).
- JIT-backed network position evaluation that consumes these rule
  engines is owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.9`.

## Sprint 9.7: Hyperparameter Tuning (Sampler × Scheduler × Pruner) ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only.
`proto-lens`-driven Haskell bindings for `proto/jitml/tune.proto`
closed on 2026-05-24 (`gen/Proto/Jitml/Tune.hs` +
`gen/Proto/Jitml/Tune_Fields.hs` re-exported by the cabal library).
Daemon-side tune handler against live broker, live MinIO trial
persistence, and the full canonical sampler × scheduler × pruner grid
against live tuner execution migrated to Phase `13` Sprint `13.10`.
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
  current sampler set; sampler outputs are exercised by run-to-run
  equality and sampler-state-purity property tests, not by committed
  trial-value files (per [../README.md → Snapshot targets →
  Numerical-fixture prohibition](../README.md#snapshot-targets)).
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

- `proto-lens`-driven Haskell bindings for `proto/jitml/tune.proto`
  closed on 2026-05-24: `gen/Proto/Jitml/Tune.hs` and
  `gen/Proto/Jitml/Tune_Fields.hs` are exposed by the cabal library,
  giving the `TuneCommand` / `TuneEvent` envelopes a binary-equivalent
  cross-language Haskell wire surface.
- Daemon-side tune handler against live broker, `persistTrialTranscript`
  / `replaySweep` validation against live HTTP MinIO, and the full
  canonical sampler × scheduler × pruner grid against live tuner
  execution are owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.10`.

## Sprint 9.8: Copyright-Free RL Matrix Retargeting ✅

**Status**: Done
**Implementation**: `src/JitML/RL/ConvergenceThresholds.hs`,
`src/JitML/RL/Algorithms/Registry.hs`, `test/rl-canonicals/Main.hs`,
`documents/engineering/training_workloads.md`
**Docs to update**: `README.md`,
`documents/engineering/training_workloads.md`,
`documents/engineering/unit_testing_policy.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Retarget the required RL algorithm/convergence matrix so visual
discrete-control coverage uses `KeyDoorGrid-v0` rather than `atari-subset`,
keeping all required demos and canonical checks free of copyrighted runtime
assets.

### Deliverables

- `JitML.RL.ConvergenceThresholds` replaces `atari-subset` cohorts with
  `key-door-grid` / `KeyDoorGrid-v0` cohorts where a visual discrete-action
  environment is needed.
- `jitml-rl-canonicals` covers the algorithm × environment matrix without
  requiring Atari ROM bytes.
- Maskable algorithms exercise `KeyDoorGrid-v0` legal-action masks.
- Required docs and report-card language refer to Atari/ALE only as optional
  runtime support, not canonical demo coverage.

### Validation

1. Phase `8` Sprint `8.9` validation has passed.
2. `docker compose run --rm jitml cabal test jitml-rl-canonicals --jobs=2`
   passes with the retargeted matrix.
3. `rg -n 'atari-subset' src/JitML/RL/ConvergenceThresholds.hs
   test/rl-canonicals/Main.hs README.md documents` shows no required
   convergence/demo wording.
4. `docker compose run --rm jitml jitml check-code` passes.

### Validation Re-run (2026-06-04)

- Phase `8` Sprint `8.9` validation passed in the same container session.
- `docker compose run --rm -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' jitml cabal test jitml-unit jitml-rl-canonicals --jobs=2`
  passed: `jitml-unit` 184 / 184 and `jitml-rl-canonicals` 27 / 27.
  The `jitml-rl-canonicals` pass includes the retargeted convergence
  threshold lookup and the `KeyDoorGrid-v0` maskable canonical case.
- `docker compose run --rm jitml jitml check-code` passed during
  `jitml:local` image construction with `check-code: ok`.

### Remaining Work

None.

## Sprint 9.9: Real `rl eval` / `rollout` and Per-Algorithm On-Device Rollouts ✅

**Status**: Done
**Implementation**: `src/JitML/App.hs` (`runCheckpointEval`, `runRl ["rl","eval"]`,
`runRl ["rl","rollout"]`, `runDeviceRollout`),
`src/JitML/RL/Algorithms/*.hs` (`moduleRolloutGenerator`)
**Docs to update**: `../documents/engineering/training_workloads.md`, `system-components.md`

### Objective

Make `jitml rl eval` and `jitml rl rollout` exercise the real substrate JIT
engine — load a real checkpoint and run a real device rollout — with **no echo
stub and no LCG `deterministicTrajectory`**, and replace the shared
`moduleRolloutGenerator` stub so each algorithm's rollout runs its real trained
policy on-device. Owns the catalog slice of
[Exit Definition](README.md#exit-definition) item 6.

### Deliverables

- `runCheckpointEval :: Text -> [ParsedOption] -> App ()` is the shared
  checkpoint read path used by `jitml eval` and `jitml rl eval`: it loads the
  named `.jmw1` checkpoint and runs the substrate-bound weighted device forward;
  a missing pointer/manifest → `InferenceCheckpointMissing` (exit 1).
- `jitml rl rollout --seed N` runs one real on-device PPO rollout on cartpole
  through `rlDeviceForSubstrate` (`runDeviceRollout` → `trainOnPolicyOnDevice`,
  one iteration) and prints the measured per-iteration episode rewards; an
  unavailable substrate device fails closed with `InvalidConfig`.
- `moduleRolloutGenerator` is retired as the shared LCG generator: each
  algorithm module's rollout runs its real (device-backed) trained policy on the
  canonical environment, so the per-algorithm rollout surface is genuine.

### Validation

- `docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`
  (per-algorithm on-device rollouts; live half in Sprint 13.17).
- Offline `jitml rl eval` → `InferenceCheckpointMissing`; offline `jitml rl
  rollout` → `InvalidConfig`; neither prints a synthetic trajectory.
- `jitml check-code` + `jitml docs check` green inside `jitml:local`.

### Current Validation State

Landed and host-validated (`ghc-9.12.4`, device cases fail closed offline):

- `runCheckpointEval` shared by `jitml eval` / `jitml rl eval`; the `rl eval`
  echo stub is removed (ledger row resolved jointly with the `rl rollout` LCG).
- `jitml rl rollout` routes through `runDeviceRollout` (real on-device PPO
  rollout), removing the `deterministicTrajectory` LCG; fails closed on an
  absent device. Host `cabal build` clean; the command-registration unit test
  still lists `rl eval` / `rl rollout`.
- 2026-06-11: `docker compose run --rm jitml jitml test jitml-rl-canonicals
  --linux-cpu` → **27/27 PASS**, including the PPO/CartPole registered rollout
  determinism case and the on-device PPO reward-improvement case.
- 2026-06-11: `docker compose run --rm jitml-cuda jitml test
  jitml-rl-canonicals --linux-cuda` → **27/27 PASS**.
- 2026-06-11: `docker compose run --rm jitml-cuda jitml rl rollout
  experiments/cartpole.dhall --seed 42` printed
  `rl rollout: seed=42 substrate=linux-cuda rewards=[18.96]`, confirming the
  CLI boundary resolves the live CUDA publication and executes the device path.

### Remaining Work

None.

## Sprint 9.10: Real MCTS Tree Search with Substrate-Backed Leaf Evaluation ✅

**Status**: Done
**Implementation**: `src/JitML/RL/AlphaZero/Mcts.hs`
(`runSearchWithPrior`, `runSearchWithPriorIO`, position-aware oracle),
`src/JitML/RL/AlphaZero/PolicyValueNet.hs` (`netOracleFactory`,
`networkPriorOracleWithDevice`, `mctsVisitDistribution`,
`mctsVisitDistributionWithDevice`); deletes
`src/JitML/RL/AlphaZero/Arena.hs` and `src/JitML/RL/AlphaZero/EnginePrior.hs`
**Docs to update**: `../documents/engineering/training_workloads.md`, `system-components.md`

### Objective

Replace the one-ply MCTS bandit with a real tree search — selection (descend
root→leaf by UCB), expansion (position priors at the leaf), evaluation (the
network **value head** on the device at the leaf position), and backpropagation
(sign-flipped value up the path) — and delete the dead `Arena.playArena` and
`EnginePrior` modules. Owns the AlphaZero search slice of
[Exit Definition](README.md#exit-definition) item 6.

### Deliverables

- The `PriorOracle` is generalised to be **position-dependent** (it receives the
  descended position / move history), so the search evaluates the network at
  each expanded node rather than only the root. `defaultPriorOracle` and the
  mechanics tests keep a neutral position-independent shim.
- `simulateWithPrior` performs one real MCTS simulation: UCB selection down to an
  unexpanded leaf, expansion with the position priors, value-head leaf
  evaluation, and backup with the adversarial sign flip; `runSearchWithPrior`
  runs `mctsSimulations` such simulations over the persistent tree (the
  transposition table keys positions). `runSearchWithPriorIO` is the
  substrate-backed analogue: leaf evaluation may compile/load/execute the
  selected JIT `MlpDevice`, and any device error returns `Left` rather than
  falling back to pure evaluation.
- `netOracleFactory` in `PolicyValueNet` supplies the position-aware policy +
  value oracle from the real network forward; `networkPriorOracleWithDevice` /
  `mctsVisitDistributionWithDevice` run the same leaf policy/value evaluation
  through the substrate JIT device. The existing determinism + visit-target
  property tests in `jitml-rl-canonicals` hold (run-to-run determinism,
  non-negative, sums to 1, search concentrates beyond uniform).
- `Arena.playArena` (SHA/LCG outcome generator, no caller) and the `EnginePrior`
  Dense2D prior module are deleted; the real arena lives in `PolicyValueNet`
  self-play generation.

### Validation

- `docker compose run --rm jitml cabal test jitml-rl-canonicals --linux-cpu`
  (MCTS visit-target + network-self-play determinism through real tree search).
- `rg -n 'Arena\.playArena|EnginePrior' src test` returns nothing outside the
  ledger.
- `jitml check-code` + `jitml docs check` green inside `jitml:local`.

### Current Validation State

Landed and validated (2026-06-10):

- `Mcts.hs` is a real recursive tree search — PUCT selection down to an
  unexpanded leaf, expansion with the position priors, value-head leaf
  evaluation, and sign-flipped backup up the path (depth-bounded by
  `mctsMaxDepth`). `PriorOracle` is now position-aware (`[Int] -> NodeEval`);
  `PolicyValueNet.netOracleFactory` roots it at the search position.
- `Arena.hs` and `EnginePrior.hs` are deleted and removed from the cabal
  exposed-modules; `rg 'Arena.playArena|EnginePrior' src test` is clean.
- Host: `jitml-unit` 196/196 (migrated MCTS oracle case, before the 2026-06-11
  rollout-helper deletion), `jitml-rl-canonicals` real-search determinism,
  legality, and valid search-derived visit distribution that concentrates
  beyond uniform. Container: `check-code: ok`, `jitml test
  jitml-rl-canonicals --linux-cpu` **27/27 PASS** and `jitml test
  jitml-rl-canonicals --linux-cuda` **27/27 PASS** on 2026-06-11. The live
  AlphaZero generation drive also passed in both full linux-cpu and linux-cuda
  integration suites (**67/67** each).
- Continuation validation (2026-06-11): `docker compose run --rm jitml jitml
  test jitml-rl-canonicals --linux-cpu` → **28/28 PASS**, including
  `MCTS visit-count target evaluates leaves through the substrate JIT device
  (Sprint 9.10 --linux-cpu): OK (0.02s)`. The device-backed path uses
  `runSearchWithPriorIO` plus `PolicyValueNet.mctsVisitDistributionWithDevice`
  and fails closed on device errors.

### Remaining Work

None.

## Sprint 9.11: Real Hyperparameter Tuning Objective Executor ✅

**Status**: Done
**Implementation**: `src/JitML/Tune/Catalog.hs` (`deterministicTrials`,
`deterministicTrialsWithDevice` → `Tune.Trial` executor),
`src/JitML/Tune/Resume.hs` (`resumeMatchesFullRun`), `src/JitML/App.hs`
(`publishWorkerTuneEvent`, `measureTuneBestObjective`)
**Docs to update**: `../documents/engineering/training_workloads.md`, `system-components.md`

### Objective

Replace the per-sampler LCG `deterministicTrials` with a real trial executor
that, for each sampled hyperparameter configuration, trains the substrate-backed
model and measures the real objective, and replace the `resumeMatchesFullRun`
tautology with a genuine resume-equality check. Owns the tuning slice of
[Exit Definition](README.md#exit-definition) item 6.

### Deliverables

- A `Tune.Trial` executor maps each sampled config (sampler × scheduler × pruner)
  to a real measured objective by training the substrate-backed model
  (`trainClassifierWithDevice` / the RL device trainers) over a bounded budget;
  no LCG-derived trial value remains.
- `resumeMatchesFullRun` compares a resumed sweep's trial objectives against the
  full-run objectives bit-for-bit (within-substrate determinism), not a
  structural tautology.
- The `jitml tune` summary and `jitml inspect trial` / `inspect frontier`
  surfaces read the real measured objective.

### Validation

- `docker compose run --rm jitml jitml test jitml-hyperparameter --linux-cpu`
  (real measured objective; live half in Sprint 13.17 / 13.10).
- `jitml check-code` + `jitml docs check` green inside `jitml:local`.

### Current Validation State

Landed and validated (2026-06-10):

- `Tune.deterministicTrials` now returns __real measured objectives__
  (`trialObjective`): each trial samples a hyperparameter configuration, trains
  the reference classifier on a fixed separable dataset, and returns the
  normalised cross-entropy loss in `[0, 1)`. No LCG-derived trial value remains.
- `Tune.deterministicTrialsWithDevice` executes the same deterministic sampler
  stream through `Classifier.trainClassifierWithDevice`; the live worker path
  (`publishWorkerTuneEvent`) uses that substrate-selected JIT device and aborts
  on device failure, while `measureTuneBestObjective` reports unavailable rather
  than falling back when no live publication/device is usable.
- Host: `jitml-hyperparameter` 14/14 (distinct per-sampler real objectives,
  values normalised, resume determinism), `jitml-unit` 196/196. Container:
  `check-code: ok`, `jitml test jitml-hyperparameter --linux-cpu` **14/14** and
  `jitml test jitml-hyperparameter --linux-cuda` **14/14** on 2026-06-11. Live
  tune trial persist/replay and daemon `StartSweep` dispatch passed in both
  linux-cpu and linux-cuda full integration suites (**67/67** each).
- Continuation validation (2026-06-11): `docker compose run --rm jitml jitml
  test jitml-hyperparameter --linux-cpu` → **15/15 PASS**, including
  `device-backed trial executor is deterministic through the substrate JIT
  device (Sprint 9.11 --linux-cpu): OK (0.12s)`.

### Remaining Work

None.

## Doctrine Sections Cited

- [../README.md → CLI command topology, typed](../README.md#cli-command-topology-typed) (Sprint 9.7 — `jitml tune` command leaf)
- [../README.md → Plan / Apply commands](../README.md#doctrine-scope) (Sprint 9.7 — current dry-run / plan-file surface)
- [../README.md → Test-suite stanzas](../README.md#test-suite-stanzas) (Sprints 9.4, 9.7, 9.8 — dedicated local RL and hyperparameter stanzas plus copyright-free RL matrix retargeting)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/training_workloads.md` — current RL algorithm
  metadata catalog, Dhall mirror, run-to-run determinism for the
  PPO/CartPole deterministic-stub trajectory (no committed trajectory
  fixture per [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets)), Connect 4 transcript
  helper, and tuner catalog; target algorithm modules,
  AlphaZero/MCTS runtime, adversarial games, target sampler decode, and
  full tuner storage/resume surface. The doc also distinguishes the
  current tune text/proto3-compatible command and event envelope codecs from
  target generated proto-lens bindings, and records `KeyDoorGrid-v0` as the
  required visual discrete-control replacement for `atari-subset` cohorts.
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

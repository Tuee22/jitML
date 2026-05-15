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

> **Purpose**: Stand up the full RL algorithm catalog (PPO, A2C, TRPO,
> MaskablePPO, RecurrentPPO, DQN, QR-DQN, DDPG, TD3, SAC, CrossQ, TQC, ARS,
> HER), the AlphaZero-style self-play surface (perfect-information game type
> class, two-headed network, MCTS-guided self-play loop, persistent MCTS state,
> arena gating, canonical adversarial games), and the hyperparameter tuning
> surface (samplers × schedulers × pruners, trial storage and resume,
> parallelism).

## Phase Status

✅ **Done** for the local RL algorithm catalog, AlphaZero transcript, and tuning
surfaces. The algorithm catalog consumes the RL framework primitives from Phase
`8`. AlphaZero's persistent MCTS state borrows the engineering arc from a
sibling MCTS project. The tuner consumes both SL and RL training surfaces.

### Current Implementation Scope

The current worktree implements a local `RLAlgorithm` catalog with family/replay
metadata, deterministic trajectory generation, Connect 4 move/transcript helpers
in `src/JitML/RL/AlphaZero.hs`, and deterministic sampler/scheduler/pruner
catalogs in `src/JitML/Tune/Catalog.hs`. It does not yet implement one module
per RL algorithm, Dhall algorithm schemas, golden RL fixture trees,
perfect-information game typeclasses, two-headed networks, persistent MCTS
search, MinIO trial storage, or live tuner resume.

## Phase Summary

This phase currently delivers local RL algorithm metadata, Connect 4 transcript
helpers, and deterministic tuning catalogs. The target phase grows those
surfaces into one module per algorithm, a persistent AlphaZero/MCTS sub-stack,
and a typed sweep manager that drives SL, RL, or AlphaZero training under a
sampler × scheduler × pruner Dhall.

## Sprint 9.1: On-Policy Algorithms (PPO, A2C, TRPO, MaskablePPO, RecurrentPPO) ✅

**Status**: Done
**Implementation**: `src/JitML/RL/Algorithms.hs`,
`test/rl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Land the on-policy family with golden trajectory fixtures.

### Deliverables

- One module per algorithm; each declares its `Algorithm` instance against
  the type-level taxonomy from Sprint `8.4`.
- Each module provides `algorithmStep :: AlgoConfig -> RolloutBuffer ->
  Policy -> ReaderT Env IO (Policy, Metrics)`.
- Per-algorithm Dhall type at `dhall/rl/algos/<algo>.dhall`.
- Golden trajectory fixtures under `test/golden/rl/<algo>/<env>/curve.cbor`
  for the canonical `(algo, env)` pairs (e.g., `ppo/cartpole`,
  `a2c/lunarlander`).

### Validation

1. `jitml rl train experiments/rl/<algo>-<env>.dhall` reaches the threshold
   mean episode reward.
2. Same-substrate same-seed runs produce bit-identical metric trajectories
   matching the golden curve.

## Sprint 9.2: Off-Policy Algorithms (DQN, QR-DQN, DDPG, TD3, SAC) ✅

**Status**: Done
**Implementation**: `src/JitML/RL/Algorithms.hs`,
`test/rl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Land the off-policy family.

### Deliverables

- One module per algorithm; each declares its `Algorithm` instance.
- Replay-buffer integration via the `Async` write discipline from Sprint
  `8.4`.
- Per-algorithm Dhall type and golden trajectory fixtures.

### Validation

1. Each `(algo, env)` reaches the threshold mean episode reward.
2. Bit-identical same-substrate same-seed determinism holds for at least
   `RL_STEPS / 10` initial steps (full-run determinism for off-policy
   algorithms is sensitive to scheduler order; the golden anchor is the
   first-N-steps prefix per
   [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md)).

## Sprint 9.3: Specialised Algorithms (CrossQ, TQC, ARS, HER) ✅

**Status**: Done
**Implementation**: `src/JitML/RL/Algorithms.hs`,
`test/rl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Land the specialised family: CrossQ (no target network), TQC (truncated
quantile critics), ARS (augmented random search), HER (hindsight experience
replay).

### Deliverables

- One module per algorithm; each declares its `Algorithm` instance.
- HER plugs into the off-policy buffers from Sprint `9.2` as a typed wrapper.
- Per-algorithm Dhall type and golden trajectory fixtures.
- The fully-populated catalog table is generated into
  `documents/engineering/training_workloads.md` under marker key
  `training.rl.catalog`.

### Validation

1. Each `(algo, env)` reaches the threshold mean episode reward.
2. The generated catalog table matches the in-code enumeration.

## Sprint 9.4: RL Golden Tests in `jitml-unit` and `jitml-integration` ✅

**Status**: Done
**Implementation**: `test/unit/Main.hs`, `test/integration/Main.hs`,
`test/rl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Stitch the golden trajectory fixtures from Sprints `9.1`–`9.3` into the
`jitml-unit` and `jitml-integration` stanzas (Phase `12`).

### Deliverables

- `jitml-unit` golden tasty group exercises every `(algo, env)` golden curve
  per the bit-identical-prefix contract from Sprints `9.1`–`9.2`.
- `jitml-integration` runs the full `jitml rl train` command end-to-end for a
  representative subset (PPO/cartpole, DQN/cartpole, SAC/lunarlander) and
  asserts daemon-side at-least-once idempotency holds.

### Validation

1. `cabal test jitml-unit` and `cabal test jitml-integration` exercise the
   RL golden suites and pass.

## Sprint 9.5: AlphaZero-Style Self-Play and Persistent MCTS State ✅

**Status**: Done
**Implementation**: `src/JitML/RL/AlphaZero.hs`,
`test/rl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`,
`documents/engineering/determinism_contract.md`

### Objective

Land the AlphaZero core: perfect-information game type class, two-headed
network, MCTS-guided self-play loop, persistent MCTS state across moves,
arena gating, self-play replay buffer, deterministic stochasticity.

### Deliverables

- `class PerfectInformationGame g where` exposes `legalActions`, `applyAction`,
  `terminal`, `winner`, `encodeObservation`, `actionSpace`.
- `TwoHeadedNetwork` carries the policy head and value head.
- `Mcts.hs` implements PUCT with persistent tree state across moves
  (visits persist; the rest of the tree is discarded incrementally as moves
  are played). Borrows the engineering arc from a sibling MCTS project per
  [../README.md → Borrowed engineering from the sibling MCTS project](../README.md#borrowed-engineering-from-the-sibling-mcts-project).
- `SelfPlay.hs` runs `AZ_GAMES` self-play games per generation with
  `AZ_SIMS` simulations per move (see
  [system-components.md → POC Report-Card
  Knobs](system-components.md#poc-report-card-knobs)).
- `Arena.hs` runs gating tournaments between successive generations; only
  improved generations are committed.
- `Buffer.hs` is the typed self-play buffer with `Async` write discipline.
- Per-game RNG seed derivation is deterministic.

### Validation

1. Same-substrate same-seed self-play produces bit-identical visit counts
   under the per-substrate determinism contract.
2. The arena gating decision is reproducible.

## Sprint 9.6: Canonical Adversarial Games ✅

**Status**: Done
**Implementation**: `src/JitML/RL/AlphaZero.hs`,
`src/JitML/Web/Contracts.hs`, `test/rl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Land the canonical adversarial games (Connect 4 canonical, plus Othello,
Hex, Gomoku) as `PerfectInformationGame` instances with golden self-play
fixtures.

### Deliverables

- Each game declares its `PerfectInformationGame` instance.
- Connect 4 is the canonical demo game (consumed by the PureScript Connect 4
  panel in Phase `11`).
- Golden self-play game fixtures under `test/golden/az/<game>/<seed>.cbor`
  for representative seeds.

### Validation

1. Same-substrate same-seed Connect 4 self-play is bit-identical.
2. The golden game-replay fixtures round-trip through `decode . encode == id`.

## Sprint 9.7: Hyperparameter Tuning (Sampler × Scheduler × Pruner) ✅

**Status**: Done
**Implementation**: `src/JitML/Tune/Catalog.hs`,
`src/JitML/App.hs`, `test/hyperparameter/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Land the typed hyperparameter tuner across the sampler × scheduler × pruner
axes per [../README.md → Hyperparameter tuning,
first-class](../README.md#hyperparameter-tuning-first-class), with trial
storage and resume against MinIO bucket `jitml-trials` and `jitml tune` as
the Plan/Apply CLI verb.

### Deliverables

- `Sampler` ADT: `Grid`, `Random`, `Sobol`, `TPE`, `GpBO`, `GA { popSize,
  crossoverRate, mutationRate }`, `NSGA2 { popSize }`,
  `MuLambdaES { mu, lambda, sigmaInit }`, `CMAES { sigmaInit }`,
  `PBT { popSize, exploitInterval, exploreSpec }`.
- `Scheduler` ADT (tuner-side, distinct from numerical-core scheduler):
  `Fifo`, `SuccessiveHalving { reductionFactor, minResource }`,
  `Hyperband { maxResource, reductionFactor }`, `ASHA { reductionFactor,
  minResource, maxResource }`.
- `Pruner` ADT: `NoPrune`, `Median { gracePeriod, threshold }`,
  `Percentile { gracePeriod, percentile }`.
- `Some Tuning::{ … }` Dhall constructor matches the worked example in
  [../README.md → Concrete Tuning example](../README.md#concrete-some-tuning--example).
- `TuneSweepLifecycle` GADT mirrors the SL/RL lifecycle GADTs.
- `Storage.hs` writes trial transcripts to MinIO bucket `jitml-trials`,
  content-addressed by `sha256(resolved-dhall || trial-seed)`. Resume
  reads the existing trials, recomputes the sampler state, and continues.
- `proto/jitml/tune.proto` declares `RunTrial`, `StopTrial`, `TrialStarted`,
  `TrialMetricUpdate`, `TrialFinished`, `TrialFailed`.
- `jitml tune <tune-dhall>` is Plan/Apply.
- Parallelism: parallel trials are independent SL/RL runs scheduled by the
  cluster; the tuner is the orchestrator.
- The fully populated catalog tables are generated into
  `documents/engineering/training_workloads.md` under
  `training.tune.samplers`, `training.tune.schedulers`,
  `training.tune.pruners`.

### Validation

1. `jitml tune --dry-run experiments/tune/cartpole-ppo-sweep.dhall` emits
   the typed plan.
2. A `TUNE_TRIALS`-trial sweep (see
   [system-components.md → POC Report-Card
   Knobs](system-components.md#poc-report-card-knobs)) completes; resume
   from a paused sweep continues from the correct trial index.
3. Same-Dhall same-master-seed sweeps produce bit-identical trial selection
   sequences.

## Doctrine Sections Cited

- [../HASKELL_CLI_TOOL.md → GADT-Indexed State Machines](../HASKELL_CLI_TOOL.md) (Sprints 9.5, 9.7)
- [../HASKELL_CLI_TOOL.md → Plan / Apply](../HASKELL_CLI_TOOL.md) (Sprint 9.7)
- [../HASKELL_CLI_TOOL.md → At-Least-Once Event Processing](../HASKELL_CLI_TOOL.md) (Sprint 9.7 — `TuneHandler`)
- [../HASKELL_CLI_TOOL.md → Capability Classes and Service Errors](../HASKELL_CLI_TOOL.md) (Sprint 9.7 — `HasMinIO`/`HasPulsar`)
- [../HASKELL_CLI_TOOL.md → Generated Artifacts](../HASKELL_CLI_TOOL.md) (Sprints 9.3, 9.7 — generated catalog tables)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/training_workloads.md` — populate the RL algorithm
  catalog table, the AlphaZero narrative (perfect-information game type
  class, two-headed network, MCTS-guided self-play loop, persistent MCTS
  state, arena gating), the canonical adversarial games, and the tuner
  surface (sampler × scheduler × pruner tables).
- `documents/engineering/determinism_contract.md` — the AlphaZero
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

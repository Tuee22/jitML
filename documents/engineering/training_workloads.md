# Training Workloads

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-8-supervised-and-rl-framework.md, ../../DEVELOPMENT_PLAN/phase-9-rl-catalog-alphazero-and-tuning.md, checkpoint_format.md, numerical_core.md
**Generated sections**: training.rl.catalog, training.tune.samplers, training.tune.schedulers, training.tune.pruners

> **Purpose**: Project-specific training-workload doctrine for jitML — the
> current local SL summaries, RL metadata/framework surfaces, AlphaZero Connect
> 4 helpers, and hyperparameter tuning catalogs, plus the target daemon-backed
> training/runtime surfaces that have not landed yet.

## SL Training Loops

`src/JitML/SL/` owns the supervised-learning surface. The current worktree has
local canonical summaries in `src/JitML/SL/Canonicals.hs`; it does not yet have
real dataset loaders, training loops, or MinIO dataset access.

- Target `Train.hs` exposes `train :: TrainingConfig -> ReaderT Env IO TrainResult`.
- Target `Loop.hs` is the typed pipeline backed by the `TrainingLifecycle` GADT
  (`Loaded → Ready → Stepping → Evaluating → Checkpointing → Finished`).
- Target `Dataset.hs` lazily fetches pinned source datasets from MinIO bucket
  `jitml-datasets`; SHA-256 verified against the experiment Dhall.

### Canonical SL Problems

| Current problem key | Owning module | Current validation |
|---------------------|---------------|--------------------|
| `mnist-shallow-mlp` | `src/JitML/SL/Canonicals.hs` | Deterministic five-point synthetic loss curve |
| `mnist-deep-mlp` | `src/JitML/SL/Canonicals.hs` | Deterministic five-point synthetic loss curve |
| `mnist-lenet` | `src/JitML/SL/Canonicals.hs` | Deterministic five-point synthetic loss curve |
| `fashion-mnist-mlp` | `src/JitML/SL/Canonicals.hs` | Deterministic five-point synthetic loss curve |
| `fashion-mnist-resnet` | `src/JitML/SL/Canonicals.hs` | Deterministic five-point synthetic loss curve |
| `cifar10-resnet20` | `src/JitML/SL/Canonicals.hs` | Deterministic five-point synthetic loss curve |
| `cifar10-resnet56` | `src/JitML/SL/Canonicals.hs` | Deterministic five-point synthetic loss curve |
| `cifar100-wide-resnet` | `src/JitML/SL/Canonicals.hs` | Deterministic five-point synthetic loss curve |
| `cifar10-vit` | `src/JitML/SL/Canonicals.hs` | Deterministic five-point synthetic loss curve |
| `tiny-imagenet-resnet50` | `src/JitML/SL/Canonicals.hs` | Deterministic five-point synthetic loss curve |
| `california-housing-mlp` | `src/JitML/SL/Canonicals.hs` | Deterministic five-point synthetic loss curve |

Live convergence thresholds and committed golden curve fixtures remain runtime
validation work.

### `jitml train` CLI

```
jitml train <experiment-dhall>
            [--resume <checkpoint-id>]
            [--dry-run | --plan-file <path>]
```

Current `jitml train` supports the Plan/Apply dry-run surface and, on normal
execution, prints the selected experiment path plus a deterministic local
canonical-problem summary. Target runtime work resolves and SHA-hashes the
experiment Dhall, reconciles prerequisites, materializes the dataset, publishes
`StartTraining` on `training.command.<mode>`, and consumes
`training.event.<mode>` through the daemon.

## RL Framework Primitives

`src/JitML/RL/` owns the framework. Per doctrine `GADT-Indexed State
Machines`, the run lifecycle is the phase-indexed GADT
`RLRunLifecycle` in `src/JitML/RL/Framework.hs`. Its current data-kind
phases are `RLCollect → RLComputeAdvantages → RLOptimise → RLEvaluate →
RLCheckpoint`; the daemon-backed runtime target lifecycle additionally
brackets these with `Loaded → Ready → … → Finished` bookend states once
`RL/Loop.hs` lands.

Current local surfaces live in `src/JitML/RL/Algorithms.hs`,
`src/JitML/RL/Environments.hs`, `src/JitML/RL/Framework.hs`, and
`src/JitML/RL/AlphaZero.hs`. They provide deterministic catalog, environment,
run-plan, lifecycle, Connect 4 transcript, canonical-game, two-headed-network,
and arena-summary helpers. The fuller target module split below is the runtime
layout the daemon-backed implementation grows into.

### Algorithm Class Taxonomy (Type-Level)

The current `AlgorithmFamily` metadata in `src/JitML/RL/Algorithms.hs`
enumerates `OnPolicy`, `OffPolicy`, `Specialized`, and `SelfPlay`. Target
runtime work grows this into a GADT-indexed `Algorithm` kind with traits:

- `OnPolicy` / `OffPolicy` / `Hierarchical` / `Recurrent`
- `MaskingCapable` (algorithm supports action masks)
- `ContinuousAction` / `DiscreteAction`
- `ImageObs` / `VectorObs`

The taxonomy is used at the type level to constrain algorithm-instance
declarations.

### Policy and Environment

- Target `Policy` carries the typed action distribution shape, parameter
  references, and the substrate-bound `KernelHandle` for inference.
- Target `Environment` typeclass plus `VecEnv` parallel-environment combinator.
- Current `src/JitML/RL/Environments.hs` provides local metadata and a
  deterministic step helper for cartpole, mountain-car, lunar-lander, and an
  atari-subset row.

### Buffers

- Replay buffer (off-policy) and rollout buffer (on-policy).
- `Async` write discipline with backpressure.
- Per-buffer message-hash-deduplicated commit log so duplicates from the
  at-least-once Pulsar consumer are absorbed.

### Schedules, Distributions, Noise, Targets, GAE, Callbacks, Logger, Evaluator

| Primitive | Variants | Owning module |
|-----------|----------|---------------|
| Primitive | Current location |
|-----------|------------------|
| Schedules | `src/JitML/RL/Framework.hs` metadata |
| Action distributions | `src/JitML/RL/Framework.hs` metadata |
| Action noise | `src/JitML/RL/Framework.hs` metadata |
| Target networks | `src/JitML/RL/Framework.hs` metadata |
| GAE | `src/JitML/RL/Framework.hs` metadata |
| Callbacks | `src/JitML/RL/Framework.hs` metadata |
| Evaluator | `src/JitML/RL/Framework.hs` metadata |

Target runtime work splits these into dedicated modules and composes them into
`RLLoop`.

### `jitml rl train` CLI

```
jitml rl train <rl-experiment-dhall>
               [--resume <checkpoint-id>]
               [--dry-run | --plan-file <path>]
```

Current normal execution prints the selected RL experiment and local algorithm
count. Target runtime work publishes `rl.command.<mode>` for the daemon's
at-least-once `RlHandler`.

## RL Algorithm Catalog

<!-- jitml:training.rl.catalog:start -->
| Algorithm | Family | Replay-backed | Current owner |
|-----------|--------|---------------|---------------|
| `PPO` | OnPolicy | no | `src/JitML/RL/Algorithms.hs` |
| `A2C` | OnPolicy | no | `src/JitML/RL/Algorithms.hs` |
| `TRPO` | OnPolicy | no | `src/JitML/RL/Algorithms.hs` |
| `MaskablePPO` | OnPolicy | no | `src/JitML/RL/Algorithms.hs` |
| `RecurrentPPO` | OnPolicy | no | `src/JitML/RL/Algorithms.hs` |
| `DQN` | OffPolicy | yes | `src/JitML/RL/Algorithms.hs` |
| `QR-DQN` | OffPolicy | yes | `src/JitML/RL/Algorithms.hs` |
| `DDPG` | OffPolicy | yes | `src/JitML/RL/Algorithms.hs` |
| `TD3` | OffPolicy | yes | `src/JitML/RL/Algorithms.hs` |
| `SAC` | OffPolicy | yes | `src/JitML/RL/Algorithms.hs` |
| `CrossQ` | Specialized | yes | `src/JitML/RL/Algorithms.hs` |
| `TQC` | Specialized | yes | `src/JitML/RL/Algorithms.hs` |
| `ARS` | Specialized | no | `src/JitML/RL/Algorithms.hs` |
| `HER` | Specialized | yes | `src/JitML/RL/Algorithms.hs` |
| `AlphaZero` | SelfPlay | no | `src/JitML/RL/Algorithms.hs` |
<!-- jitml:training.rl.catalog:end -->

`dhall/rl/Schema.dhall` is the current Dhall mirror for the local Haskell
algorithm catalog and is audited by `JitML.RL.Schema` plus the Haskell lint
stack. `test/golden/rl/ppo/cartpole/trajectory.txt` pins the current
PPO/CartPole deterministic trajectory. Per-algorithm runtime modules, richer
Dhall types at `dhall/rl/algos/<algo>.dhall`, and full trajectory fixture
coverage under `test/golden/rl/<algo>/<env>/` remain target work.

For off-policy algorithms, the bit-equality golden anchor is the first-N-
steps prefix per [determinism_contract.md → Same-Substrate Bit-Equality (RL
Caveat)](determinism_contract.md#same-substrate-bit-equality-rl-caveat).

## AlphaZero-Style Self-Play

The current AlphaZero surface lives in `src/JitML/RL/AlphaZero.hs`. It provides
Connect 4 state/move helpers, deterministic transcript summaries, local game
metadata, two-headed-network metadata, and arena summaries. A persistent
AlphaZero/MCTS stack remains target runtime work.

| Component | Current / target |
|-----------|------------------|
| Connect 4 helpers | Current: `src/JitML/RL/AlphaZero.hs` |
| Perfect-information game metadata | Current: `src/JitML/RL/AlphaZero.hs` |
| Two-headed network metadata | Current: `src/JitML/RL/AlphaZero.hs` |
| MCTS with PUCT and persistent tree state | Target runtime module |
| Self-play loop and replay buffer | Target runtime module |
| Arena gating | Current summary helper; target runtime module |

### Persistent MCTS State

The current `MctsState` is a small local metadata record with visit count and a
prior seed. Persistent visits across moves remain target runtime work.

### Deterministic Stochasticity

Per-game RNG seeds derive from `splitmix64(experimentSeed, gameIndex)`. The
MCTS root-noise seed is derived from the per-game seed. Same-substrate same-
seed self-play produces bit-identical visit counts.

### Canonical Adversarial Games

| Game | Owning module |
|------|---------------|
| Connect 4 | `src/JitML/RL/AlphaZero.hs` metadata and helper |
| Othello | `src/JitML/RL/AlphaZero.hs` metadata only |
| Hex | `src/JitML/RL/AlphaZero.hs` metadata only |
| Gomoku | `src/JitML/RL/AlphaZero.hs` metadata only |

Connect 4 is the canonical demo game consumed by the PureScript Connect 4
panel metadata. `test/golden/alphazero/connect4-transcript.txt` pins the current
local transcript shape; fuller self-play game fixtures remain target work.

## Hyperparameter Tuning

`src/JitML/Tune/` owns the hyperparameter tuner surface. The current local
catalog lives in `src/JitML/Tune/Catalog.hs` and follows the sampler x
scheduler x pruner shape from [../README.md → Hyperparameter tuning,
first-class](../../README.md#hyperparameter-tuning-first-class).

`TuneSweepLifecycle` GADT (`Sampled → Scheduled → Running → Pruned →
Reported → Finished`) is the typed lifecycle.

### Samplers

<!-- jitml:training.tune.samplers:start -->
| Constructor | Current scope |
|-------------|---------------|
| `Sobol` | Generated from current Haskell catalog |
| `Random` | Generated from current Haskell catalog |
| `GeneticAlgorithm` | Generated from current Haskell catalog |
| `EvolutionStrategies` | Generated from current Haskell catalog |
<!-- jitml:training.tune.samplers:end -->

### Schedulers (tuner-side)

<!-- jitml:training.tune.schedulers:start -->
| Constructor | Current scope |
|-------------|---------------|
| `Fifo` | Generated from current Haskell catalog |
| `SuccessiveHalving` | Generated from current Haskell catalog |
| `Hyperband` | Generated from current Haskell catalog |
| `ASHA` | Generated from current Haskell catalog |
<!-- jitml:training.tune.schedulers:end -->

### Pruners

<!-- jitml:training.tune.pruners:start -->
| Constructor | Current scope |
|-------------|---------------|
| `NoPruner` | Generated from current Haskell catalog |
| `MedianPruner` | Generated from current Haskell catalog |
| `PercentilePruner` | Generated from current Haskell catalog |
<!-- jitml:training.tune.pruners:end -->

### Trial Storage and Resume

Target trial transcripts are written to MinIO bucket `jitml-trials`, content-
addressed by `sha256(resolved-dhall || trial-seed)`. Target resume reads
existing trials, recomputes the sampler state, and continues from the correct
trial index.

The current local surface in `src/JitML/Tune/Catalog.hs` exposes
`trialStorageKey`, `resumeMatchesFullRun`, and `renderTrialResumeSummary` for
deterministic key and resume-equality checks before the live MinIO writer lands.
`test/golden/tune/` pins the current Sobol and GeneticAlgorithm trial streams.

### `jitml tune` CLI

```
jitml tune <tune-dhall>
           [--resume <sweep-id>]
           [--dry-run | --plan-file <path>]
```

Current normal execution prints deterministic local trial values. Target
runtime work publishes `tune.command.<mode>` for the daemon's at-least-once
`TuneHandler`.

### Worked Example

The `Some Tuning::{ … }` Dhall constructor matches the worked example in
[../README.md → Concrete `Some Tuning::{ … }`
example](../../README.md#concrete-some-tuning--example).

## Cross-References

- [../../README.md → RL framework primitives](../../README.md#rl-framework-primitives)
- [../../README.md → RL algorithm catalog](../../README.md#rl-algorithm-catalog)
- [../../README.md → AlphaZero-style self-play and persistent MCTS state](../../README.md#alphazero-style-self-play-and-persistent-mcts-state)
- [../../README.md → Hyperparameter tuning, first-class](../../README.md#hyperparameter-tuning-first-class)
- [numerical_core.md](numerical_core.md)
- [checkpoint_format.md](checkpoint_format.md)
- [daemon_architecture.md](daemon_architecture.md)
- [../../DEVELOPMENT_PLAN/phase-8-supervised-and-rl-framework.md](../../DEVELOPMENT_PLAN/phase-8-supervised-and-rl-framework.md)
- [../../DEVELOPMENT_PLAN/phase-9-rl-catalog-alphazero-and-tuning.md](../../DEVELOPMENT_PLAN/phase-9-rl-catalog-alphazero-and-tuning.md)

# Training Workloads

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-8-supervised-and-rl-framework.md, ../../DEVELOPMENT_PLAN/phase-9-rl-catalog-alphazero-and-tuning.md, checkpoint_format.md, numerical_core.md
**Generated sections**: training.rl.catalog, training.tune.samplers, training.tune.schedulers, training.tune.pruners

> **Purpose**: Project-specific training-workload doctrine for jitML — the SL
> training loop and canonical SL problem set, the RL framework primitives,
> the RL algorithm catalog (PPO, A2C, ..., HER), AlphaZero-style self-play
> with persistent MCTS state, and hyperparameter tuning across the
> sampler × scheduler × pruner axes.

## SL Training Loops

`src/JitML/SL/` owns the supervised training stack.

- `Train.hs` exposes `train :: TrainingConfig -> ReaderT Env IO TrainResult`.
- `Loop.hs` is the typed pipeline backed by the `TrainingLifecycle` GADT
  (`Loaded → Ready → Stepping → Evaluating → Checkpointing → Finished`).
- `Dataset.hs` lazily fetches pinned source datasets from MinIO bucket
  `jitml-datasets`; SHA-256 verified against the experiment Dhall.

### Canonical SL Problems

| Problem | Owning module | Threshold methodology | Golden curve fixture |
|---------|---------------|-----------------------|----------------------|
| MNIST shallow MLP | `src/JitML/SL/Problems/Mnist.hs` | README literature target, converted to k=5 median-minus-slack golden | `test/golden/sl/mnist-shallow-mlp/curve.cbor` |
| MNIST deep MLP | `src/JitML/SL/Problems/Mnist.hs` | README literature target, converted to k=5 median-minus-slack golden | `test/golden/sl/mnist-deep-mlp/curve.cbor` |
| MNIST LeNet-style CNN | `src/JitML/SL/Problems/Mnist.hs` | README literature target, converted to k=5 median-minus-slack golden | `test/golden/sl/mnist-lenet/curve.cbor` |
| Fashion-MNIST shallow MLP | `src/JitML/SL/Problems/FashionMnist.hs` | README literature target, converted to k=5 median-minus-slack golden | `test/golden/sl/fashion-mnist-mlp/curve.cbor` |
| Fashion-MNIST small ResNet | `src/JitML/SL/Problems/FashionMnist.hs` | README literature target, converted to k=5 median-minus-slack golden | `test/golden/sl/fashion-mnist-resnet/curve.cbor` |
| CIFAR-10 ResNet-20 | `src/JitML/SL/Problems/Cifar.hs` | README literature target, converted to k=5 median-minus-slack golden | `test/golden/sl/cifar10-resnet20/curve.cbor` |
| CIFAR-10 ResNet-56 | `src/JitML/SL/Problems/Cifar.hs` | README literature target, converted to k=5 median-minus-slack golden | `test/golden/sl/cifar10-resnet56/curve.cbor` |
| CIFAR-100 Wide ResNet-28-10 | `src/JitML/SL/Problems/Cifar.hs` | README literature target, converted to k=5 median-minus-slack golden | `test/golden/sl/cifar100-wide-resnet/curve.cbor` |
| CIFAR-10 small ViT | `src/JitML/SL/Problems/Cifar.hs` | README literature target, converted to k=5 median-minus-slack golden | `test/golden/sl/cifar10-vit/curve.cbor` |
| Tiny ImageNet ResNet-50 | `src/JitML/SL/Problems/TinyImagenet.hs` | README literature target, converted to k=5 median-minus-slack golden | `test/golden/sl/tiny-imagenet-resnet50/curve.cbor` |
| California Housing MLP | `src/JitML/SL/Problems/CaliforniaHousing.hs` | README regression target, converted to k=5 median-plus-slack golden | `test/golden/sl/california-housing-mlp/curve.cbor` |

The convergence curve is the per-step loss / per-epoch eval-accuracy series.
The golden anchor holds bit-identically under same-substrate determinism per
[determinism_contract.md](determinism_contract.md).

### `jitml train` CLI

```
jitml train <experiment-dhall>
            [--resume <checkpoint-id>]
            [--dry-run | --plan-file <path>]
```

Plan/Apply: resolve and SHA-hash the experiment Dhall, reconcile
prerequisites, materialise the dataset, publish `StartTraining` on
`training.command.<mode>`, subscribe to `training.event.<mode>`. The daemon's
at-least-once `TrainingHandler` consumes the command per
[daemon_architecture.md → At-Least-Once Pulsar
Consumer](daemon_architecture.md#at-least-once-pulsar-consumer).

## RL Framework Primitives

`src/JitML/RL/` owns the framework. Per doctrine `GADT-Indexed State
Machines`, `RLRunLifecycle` (`Loaded → Ready → Collecting → Optimising →
Evaluating → Checkpointing → Finished`) is the typed lifecycle.

### Algorithm Class Taxonomy (Type-Level)

`Algorithm` is a GADT-indexed kind with traits:

- `OnPolicy` / `OffPolicy` / `Hierarchical` / `Recurrent`
- `MaskingCapable` (algorithm supports action masks)
- `ContinuousAction` / `DiscreteAction`
- `ImageObs` / `VectorObs`

The taxonomy is used at the type level to constrain algorithm-instance
declarations.

### Policy and Environment

- `Policy` carries the typed action distribution shape, parameter
  references, and the substrate-bound `KernelHandle` for inference.
- `Environment` typeclass plus `VecEnv` parallel-environment combinator.
- Each canonical environment (cartpole, mountain-car, lunar-lander,
  Atari subset) is an in-process Haskell implementation with deterministic
  seeded `reset` and `step`.

### Buffers

- Replay buffer (off-policy) and rollout buffer (on-policy).
- `Async` write discipline with backpressure.
- Per-buffer message-hash-deduplicated commit log so duplicates from the
  at-least-once Pulsar consumer are absorbed.

### Schedules, Distributions, Noise, Targets, GAE, Callbacks, Logger, Evaluator

| Primitive | Variants | Owning module |
|-----------|----------|---------------|
| Schedule | `ConstantSched`, `LinearSched`, `ExponentialSched`, `PiecewiseSched` | `src/JitML/RL/Schedule.hs` |
| Action distribution | `Categorical`, `Gaussian`, `Bernoulli`, `MaskedCategorical`, `MixtureGaussian` | `src/JitML/RL/Distribution.hs` |
| Action noise | `Gaussian`, `OrnsteinUhlenbeck`, `ParameterSpaceNoise` | `src/JitML/RL/Noise.hs` |
| Target network | Polyak averaging step + periodic-copy mode | `src/JitML/RL/Target.hs` |
| GAE | `GAE :: GAEParams -> Trajectory -> Advantages` deterministic | `src/JitML/RL/GAE.hs` |
| Callback | Typed composable hook with `onStepEnd`, `onEpisodeEnd`, `onCheckpoint` | `src/JitML/RL/Callback.hs` |
| Logger | Multi-sink (TensorBoard + Pulsar `rl.event.<mode>` + Prometheus + stdout) | `src/JitML/RL/Logger.hs` |
| Evaluator | `RL_EVAL_EPISODES` deterministic eval episodes | `src/JitML/RL/Eval.hs` |

`src/JitML/RL/Loop.hs` composes these into `RLLoop`, the typed pipeline that
the algorithm catalog plugs into.

### `jitml rl train` CLI

```
jitml rl train <rl-experiment-dhall>
               [--resume <checkpoint-id>]
               [--dry-run | --plan-file <path>]
```

Plan/Apply. Daemon's at-least-once `RlHandler` consumes
`rl.command.<mode>`.

## RL Algorithm Catalog

<!-- jitml:training.rl.catalog:start -->
| Algorithm | Family | Owning module | Notes |
|-----------|--------|---------------|-------|
| PPO | On-policy | `src/JitML/RL/Algos/Ppo.hs` | Clipped objective; entropy bonus |
| A2C | On-policy | `src/JitML/RL/Algos/A2c.hs` | Synchronous A3C variant |
| TRPO | On-policy | `src/JitML/RL/Algos/Trpo.hs` | Trust region |
| MaskablePPO | On-policy + `MaskingCapable` | `src/JitML/RL/Algos/MaskablePpo.hs` | PPO with action masks |
| RecurrentPPO | On-policy + `Recurrent` | `src/JitML/RL/Algos/RecurrentPpo.hs` | PPO with LSTM/GRU policy |
| DQN | Off-policy + `DiscreteAction` | `src/JitML/RL/Algos/Dqn.hs` | Vanilla deep Q |
| QR-DQN | Off-policy + `DiscreteAction` | `src/JitML/RL/Algos/QrDqn.hs` | Quantile regression DQN |
| DDPG | Off-policy + `ContinuousAction` | `src/JitML/RL/Algos/Ddpg.hs` | Deterministic policy gradient |
| TD3 | Off-policy + `ContinuousAction` | `src/JitML/RL/Algos/Td3.hs` | Twin-delayed DDPG |
| SAC | Off-policy + `ContinuousAction` | `src/JitML/RL/Algos/Sac.hs` | Maximum-entropy actor-critic |
| CrossQ | Off-policy + `ContinuousAction` | `src/JitML/RL/Algos/CrossQ.hs` | No target network |
| TQC | Off-policy + `ContinuousAction` | `src/JitML/RL/Algos/Tqc.hs` | Truncated quantile critics |
| ARS | Hierarchical + parameter-space search | `src/JitML/RL/Algos/Ars.hs` | Augmented random search |
| HER | Off-policy wrapper | `src/JitML/RL/Algos/Her.hs` | Hindsight experience replay |
<!-- jitml:training.rl.catalog:end -->

Per-algorithm Dhall types at `dhall/rl/algos/<algo>.dhall`. Golden trajectory
fixtures under `test/golden/rl/<algo>/<env>/curve.cbor`.

For off-policy algorithms, the bit-equality golden anchor is the first-N-
steps prefix per [determinism_contract.md → Same-Substrate Bit-Equality (RL
Caveat)](determinism_contract.md#same-substrate-bit-equality-rl-caveat).

## AlphaZero-Style Self-Play

`src/JitML/AlphaZero/` owns the AlphaZero stack. Borrows the engineering arc
from a sibling MCTS project per [../README.md → Borrowed engineering from the
sibling MCTS project](../../README.md#borrowed-engineering-from-the-sibling-mcts-project).

| Component | Module |
|-----------|--------|
| Perfect-information game type class | `src/JitML/AlphaZero/Game.hs` |
| Two-headed network (policy + value) | `src/JitML/AlphaZero/Network.hs` |
| MCTS with PUCT and persistent tree state | `src/JitML/AlphaZero/Mcts.hs` |
| Self-play loop | `src/JitML/AlphaZero/SelfPlay.hs` |
| Arena gating | `src/JitML/AlphaZero/Arena.hs` |
| Self-play replay buffer (`Async` writes) | `src/JitML/AlphaZero/Buffer.hs` |

### Persistent MCTS State

Visits persist across moves within a single game; the rest of the tree is
discarded incrementally as moves are played.

### Deterministic Stochasticity

Per-game RNG seeds derive from `splitmix64(experimentSeed, gameIndex)`. The
MCTS root-noise seed is derived from the per-game seed. Same-substrate same-
seed self-play produces bit-identical visit counts.

### Canonical Adversarial Games

| Game | Owning module |
|------|---------------|
| Connect 4 (canonical demo game) | `src/JitML/AlphaZero/Games/Connect4.hs` |
| Othello | `src/JitML/AlphaZero/Games/Othello.hs` |
| Hex | `src/JitML/AlphaZero/Games/Hex.hs` |
| Gomoku | `src/JitML/AlphaZero/Games/Gomoku.hs` |

Connect 4 is the canonical demo game consumed by the PureScript Connect 4
panel. Golden self-play game fixtures under `test/golden/az/<game>/<seed>.cbor`.

## Hyperparameter Tuning

`src/JitML/Tune/` owns the hyperparameter tuner. The tuning surface follows
the sampler × scheduler × pruner shape from [../README.md → Hyperparameter
tuning, first-class](../../README.md#hyperparameter-tuning-first-class).

`TuneSweepLifecycle` GADT (`Sampled → Scheduled → Running → Pruned →
Reported → Finished`) is the typed lifecycle.

### Samplers

<!-- jitml:training.tune.samplers:start -->
| Constructor | Notes |
|-------------|-------|
| `Grid` | Cartesian product of declared values |
| `Random` | Uniform random sampling |
| `Sobol` | Low-discrepancy quasi-random sequence |
| `TPE` | Tree-structured Parzen estimator |
| `GpBO` | Gaussian-process Bayesian optimisation |
| `GA` | Genetic algorithm with `popSize`, `crossoverRate`, `mutationRate` |
| `NSGA2` | Multi-objective GA with `popSize` |
| `MuLambdaES` | (μ,λ)-evolution strategy with `mu`, `lambda`, `sigmaInit` |
| `CMAES` | Covariance matrix adaptation ES with `sigmaInit` |
| `PBT` | Population-based training with `popSize`, `exploitInterval`, `exploreSpec` |
<!-- jitml:training.tune.samplers:end -->

### Schedulers (tuner-side)

<!-- jitml:training.tune.schedulers:start -->
| Constructor | Notes |
|-------------|-------|
| `Fifo` | First-in-first-out trial scheduler |
| `SuccessiveHalving` | `reductionFactor`, `minResource` |
| `Hyperband` | `maxResource`, `reductionFactor` |
| `ASHA` | Async successive halving with `reductionFactor`, `minResource`, `maxResource` |
<!-- jitml:training.tune.schedulers:end -->

### Pruners

<!-- jitml:training.tune.pruners:start -->
| Constructor | Notes |
|-------------|-------|
| `NoPrune` | No pruning |
| `Median` | `gracePeriod`, `threshold` |
| `Percentile` | `gracePeriod`, `percentile` |
<!-- jitml:training.tune.pruners:end -->

### Trial Storage and Resume

Trial transcripts are written to MinIO bucket `jitml-trials`, content-
addressed by `sha256(resolved-dhall || trial-seed)`. Resume reads existing
trials, recomputes the sampler state, continues from the correct trial
index.

### `jitml tune` CLI

```
jitml tune <tune-dhall>
           [--resume <sweep-id>]
           [--dry-run | --plan-file <path>]
```

Plan/Apply. Daemon's at-least-once `TuneHandler` consumes
`tune.command.<mode>`.

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

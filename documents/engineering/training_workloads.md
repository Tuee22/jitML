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
local canonical summaries in `src/JitML/SL/Canonicals.hs`, typed dataset
references in `src/JitML/SL/Dataset.hs`, a deterministic GADT-shaped loop in
`src/JitML/SL/Loop.hs`, and `train :: TrainingConfig -> ReaderT Env m
TrainResult` in `src/JitML/SL/Train.hs`.

- Current `Train.hs` exposes a deterministic local training result over the
  canonical problem catalog.
- Current `Loop.hs` is the typed pipeline backed by the `TrainingLifecycle`
  GADT phases and deterministic convergence curves.
- Current `Dataset.hs` renders pinned dataset object keys, maps them to bucket
  `jitml-datasets`, exposes `fetchDatasetRef` through the `HasMinIO`
  capability, and verifies fetched bytes against the pinned SHA-256. The
  filesystem-backed `HasMinIO` test covers the capability boundary; live
  routed MinIO fetch from `jitml train` / `TrainingHandler` remains target
  runtime work.

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

Convergence is asserted statistically by `jitml-sl-canonicals`: the
median over a fixed-seed pool clears a sanity threshold derived from
the problem's literature target at test time. No per-substrate `.txt`
loss-curve fixtures are committed — see
[unit_testing_policy.md → Snapshot Tests and the Prohibition on
Numerical Fixtures](unit_testing_policy.md#snapshot-tests-and-the-prohibition-on-numerical-fixtures).

### `jitml train` CLI

```
jitml train <experiment-dhall>
            [--resume <checkpoint-id>]
            [--dry-run | --plan-file <path>]
```

Current `jitml train` supports the Plan/Apply dry-run surface and, on normal
execution, prints the selected experiment path plus a deterministic local
canonical-problem summary. **Sprint 13.4 real-MNIST path**: when the worker
runs in cluster context against a dataset with canonical image + label
artefacts staged in MinIO (MNIST), `JitML.App.attemptRealMnistTraining`
fetches `jitml-datasets/MNIST/{train,test}/{data,labels}.bin`, gunzips
(`JitML.SL.Dataset.maybeGunzip`), IDX-parses, and trains the real
differentiable softmax classifier (`JitML.SL.Classifier`, on the
`JitML.Numerics.Mlp` seam) over the bytes — example count / epochs / test
size capped by the typed Dhall `RunConfig` so a live run stays tractable under
the pure-Haskell MLP. The worker decodes these caps from Dhall, not environment
variables: Phase `5` Sprint `5.7` retires the former `JITML_SL_TRAIN_LIMIT` /
`JITML_SL_EPOCHS` / `JITML_SL_TEST_LIMIT` env IPC in favour of the typed
`RunConfig` per the `Application Environment` doctrine (see
[Development Plan → Reopened phases](../../DEVELOPMENT_PLAN/README.md#reopened-phases-2026-05-29)). The measured `train_acc` / `test_acc` are reported and the published
`EpochCompleted` loss becomes the live measurement. Image + label blobs are
staged via `jitml internal upload-dataset --name MNIST --split <split>
--artifact {images,labels} --path <gz>`, SHA-verified against
`JitML.SL.Dataset.canonicalArtifactSha256For`. The operationally-heavy live
full-MNIST statistical-convergence assertion remains Sprint 13.4
Remaining Work. `src/JitML/Proto/Training.hs` defines the typed
`TrainingCommand` envelopes and deterministic text render/parse round-trips
for `StartTraining` and `StopTraining`; `encodeTrainingCommandProto` and
`decodeTrainingCommandProto` round-trip the current command oneof through
proto3-compatible bytes via `JitML.Proto.Wire`. `encodeTrainingEventProto`
and `decodeTrainingEventProto` round-trip the current `TrainingEvent` oneof,
including checkpoint metric entries, through the same local wire helper.
Generated cross-language proto-lens output remains target work. Target runtime work
resolves and SHA-hashes the experiment Dhall,
reconciles prerequisites, materializes the dataset, publishes `StartTraining`
on `training.command.<mode>`, and consumes
`training.event.<mode>` through the daemon.

## RL Framework Primitives

`src/JitML/RL/` owns the framework. Per doctrine `GADT-Indexed State
Machines`, the run lifecycle is the phase-indexed GADT
`RLRunLifecycle` in `src/JitML/RL/Framework.hs`. Its current data-kind
phases are `RLCollect → RLComputeAdvantages → RLOptimise → RLEvaluate →
RLCheckpoint`; `src/JitML/RL/Loop.hs` provides the deterministic local
`RLLoop` / `runRLLoop` surface, including deterministic rollout transition
capture into the local `ReplayBuffer`. The daemon-backed runtime target
additionally brackets this with live load/ready/serve/drain states.

Current local surfaces live in `src/JitML/RL/Algorithms.hs`,
`src/JitML/RL/Environments.hs`, `src/JitML/RL/Framework.hs`, and
`src/JitML/RL/{Policy,VecEnv,Buffer,AsyncBuffer,Loop}.hs`, plus one module per
traditional algorithm under `src/JitML/RL/Algorithms/` and the AlphaZero
substack under `src/JitML/RL/AlphaZero/`. They provide deterministic catalog,
environment, run-plan, lifecycle, policy, buffer, loop, per-algorithm module,
canonical-game, MCTS, self-play, and arena helpers. Live environment stepping,
network forward/backward passes, and daemon-backed persistence remain target
runtime work.

### Algorithm Class Taxonomy (Type-Level)

The current `AlgorithmFamily` metadata in `src/JitML/RL/Algorithms.hs`
enumerates `OnPolicy`, `OffPolicy`, `Specialized`, and `SelfPlay`; the concrete
per-algorithm modules are aggregated by
`src/JitML/RL/Algorithms/Registry.hs`. Target runtime work grows this into a
GADT-indexed `Algorithm` kind with traits:

- `OnPolicy` / `OffPolicy` / `Hierarchical` / `Recurrent`
- `MaskingCapable` (algorithm supports action masks)
- `ContinuousAction` / `DiscreteAction`
- `ImageObs` / `VectorObs`

The taxonomy is used at the type level to constrain algorithm-instance
declarations.

### Policy and Environment

- Current `Policy` carries typed policy metadata, parameter references, the
  substrate binding, and the substrate-bound `KernelHandle` model id; target
  runtime work loads and executes the referenced kernel.
- Current `RLEnvironment` metadata plus `VecEnv` combinator cover local
  deterministic stepping; live simulator bindings remain target work.
- Current `src/JitML/RL/Environments.hs` provides local metadata and a
  deterministic step helper for cartpole, mountain-car, lunar-lander, and an
  atari-subset row.

### Buffers

- Current `ReplayBuffer` covers off-policy and on-policy rollout storage with
  deterministic sampling.
- Current `AsyncBuffer` provides the bounded async write discipline and drain
  boundary.
- Target work backs the async sink with live `HasMinIO` and adds the
  message-hash-deduplicated commit log so duplicates from the at-least-once
  Pulsar consumer are absorbed.

### Schedules, Distributions, Noise, Targets, GAE, Callbacks, Logger, Evaluator

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
count. `src/JitML/Proto/Rl.hs` defines the typed `RlCommand` envelopes and
deterministic text render/parse round-trips for `StartRLRun` and `StopRLRun`;
`encodeRlCommandProto` and `decodeRlCommandProto` round-trip the current
command oneof through proto3-compatible bytes via `JitML.Proto.Wire`.
`encodeRlEventProto` and `decodeRlEventProto` round-trip the current
`RlEvent` oneof through the same local wire helper. Generated cross-language
proto-lens output remains target work. Target runtime work publishes
`rl.command.<mode>` for the daemon's at-least-once `RlHandler`.

## RL Algorithm Catalog

<!-- jitml:training.rl.catalog:start -->
| Algorithm | Family | Replay-backed | Hyperparameters | Module |
|-----------|--------|---------------|-----------------|--------|
| `PPO` | OnPolicy | no | 10 | `src/JitML/RL/Algorithms/Ppo.hs` |
| `A2C` | OnPolicy | no | 7 | `src/JitML/RL/Algorithms/A2c.hs` |
| `TRPO` | OnPolicy | no | 7 | `src/JitML/RL/Algorithms/Trpo.hs` |
| `MaskablePPO` | OnPolicy | no | 6 | `src/JitML/RL/Algorithms/MaskablePpo.hs` |
| `RecurrentPPO` | OnPolicy | no | 6 | `src/JitML/RL/Algorithms/RecurrentPpo.hs` |
| `DQN` | OffPolicy | yes | 9 | `src/JitML/RL/Algorithms/Dqn.hs` |
| `QR-DQN` | OffPolicy | yes | 6 | `src/JitML/RL/Algorithms/QrDqn.hs` |
| `DDPG` | OffPolicy | yes | 7 | `src/JitML/RL/Algorithms/Ddpg.hs` |
| `TD3` | OffPolicy | yes | 7 | `src/JitML/RL/Algorithms/Td3.hs` |
| `SAC` | OffPolicy | yes | 7 | `src/JitML/RL/Algorithms/Sac.hs` |
| `CrossQ` | Specialized | yes | 6 | `src/JitML/RL/Algorithms/CrossQ.hs` |
| `TQC` | Specialized | yes | 6 | `src/JitML/RL/Algorithms/Tqc.hs` |
| `ARS` | Specialized | no | 5 | `src/JitML/RL/Algorithms/Ars.hs` |
| `HER` | Specialized | yes | 5 | `src/JitML/RL/Algorithms/Her.hs` |
| `AlphaZero` | SelfPlay | no | 0 | `src/JitML/RL/AlphaZero/` |
<!-- jitml:training.rl.catalog:end -->

`dhall/rl/Schema.dhall` is the current Dhall mirror for the local Haskell
algorithm catalog and is audited by `JitML.RL.Schema` plus the Haskell lint
stack. The traditional algorithms have concrete modules under
`src/JitML/RL/Algorithms/{Ppo,A2c,Trpo,MaskablePpo,RecurrentPpo,Dqn,QrDqn,Ddpg,Td3,Sac,CrossQ,Tqc,Ars,Her}.hs`
aggregated by `Registry.algorithmModuleRegistry`. PPO/CartPole determinism
is asserted by `jitml-rl-canonicals` as run-to-run equality on the same
substrate and seed (two fresh runs compared against each other). Richer Dhall
types at `dhall/rl/algos/<algo>.dhall` and real network/update logic remain
target work. Per-algorithm trajectory `.txt` fixtures are explicitly
**not** committed — see [unit_testing_policy.md → Snapshot Tests and
the Prohibition on Numerical Fixtures](unit_testing_policy.md#snapshot-tests-and-the-prohibition-on-numerical-fixtures).

For off-policy algorithms, the bit-equality anchor is the first-N-
steps prefix per [determinism_contract.md → Same-Substrate Bit-Equality (RL
Caveat)](determinism_contract.md#same-substrate-bit-equality-rl-caveat),
again compared run-to-run rather than against a stored prefix.

## AlphaZero-Style Self-Play

The current AlphaZero surface lives in `src/JitML/RL/AlphaZero.hs` plus
`src/JitML/RL/AlphaZero/{Mcts,SelfPlay,Arena}.hs`. It provides per-game
state/move helpers for Connect 4, Othello, Hex, and Gomoku, deterministic
transcript summaries, local game metadata, two-headed-network metadata,
persistent MCTS transposition-table helpers, self-play buffer hashing, and
arena promotion summaries. Real network evaluation and live checkpoint
persistence remain target runtime work.

| Component | Current / target |
|-----------|------------------|
| Connect 4 helpers | Current: `src/JitML/RL/AlphaZero.hs` |
| Perfect-information game metadata | Current: `src/JitML/RL/AlphaZero.hs` |
| Two-headed network metadata | Current: `src/JitML/RL/AlphaZero.hs` |
| MCTS with PUCT and persistent tree state | Current deterministic module: `src/JitML/RL/AlphaZero/Mcts.hs`; target real network prior/evaluator |
| Self-play loop and replay buffer | Current deterministic module: `src/JitML/RL/AlphaZero/SelfPlay.hs`; target live MinIO checkpoint persistence |
| Arena gating | Current deterministic module: `src/JitML/RL/AlphaZero/Arena.hs`; target measured candidate-vs-reference evaluation |

### Persistent MCTS State

The top-level `MctsState` is a small local metadata record with visit count and
a prior seed. `JitML.RL.AlphaZero.Mcts` now provides the persistent
`TranspositionTable`, `TranspositionKey`, and `runSearchWithTable` helpers;
target runtime work replaces the deterministic prior with a real two-headed
network evaluator.

### Deterministic Stochasticity

Per-game RNG seeds derive from `splitmix64(experimentSeed, gameIndex)`. The
MCTS root-noise seed is derived from the per-game seed. Same-substrate same-
seed self-play produces bit-identical visit counts.

### Canonical Adversarial Games

| Game | Owning module |
|------|---------------|
| Connect 4 | `src/JitML/RL/AlphaZero.hs` metadata, `initialConnect4`, `applyMove`, transcript helper, and two-headed network |
| Othello | `src/JitML/RL/AlphaZero.hs` metadata, `initialOthello`, `othelloApplyMove`, transcript helper, and two-headed network |
| Hex | `src/JitML/RL/AlphaZero.hs` metadata, `initialHex`, `hexApplyMove`, transcript helper, and two-headed network |
| Gomoku | `src/JitML/RL/AlphaZero.hs` metadata, `initialGomoku`, `gomokuApplyMove`, transcript helper, and two-headed network |

Connect 4 is the canonical demo game consumed by the PureScript Connect 4
panel metadata. Per-game transcript files are explicitly **not** committed
(MCTS visit counts depend on RNG host word size, transcendental impl, and
PUCT-tie-breaking float order, all of which vary across substrates);
correctness is asserted as run-to-run equality on the same substrate / seed
plus rule-conformance properties (every emitted move is legal under
`nextLegalMove`, terminal states match `gameTerminal`, draws are detected
canonically). See [unit_testing_policy.md → Snapshot Tests and the
Prohibition on Numerical Fixtures](unit_testing_policy.md#snapshot-tests-and-the-prohibition-on-numerical-fixtures).

## Hyperparameter Tuning

`src/JitML/Tune/` owns the hyperparameter tuner surface. The current local
catalog lives in `src/JitML/Tune/Catalog.hs` and follows the sampler x
scheduler x pruner shape from [../README.md → Hyperparameter tuning,
first-class](../../README.md#hyperparameter-tuning-first-class).
The checked-in `experiments/mnist-tune.dhall` file is the target-shape
`Some Tuning::{ ... }` worked example with a TPE sampler. The current Haskell
catalog below covers the full target sampler set, decodes that fixture into
the local tuning ADT, and renders a deterministic `jitml tune` plan; live
daemon-backed trial execution remains target work.
`jitml-hyperparameter` consumes the `tune_trials` and
`tune_budget_per_trial` report-card knobs from `cabal.project` for the local
TPE trial-budget assertion.
`src/JitML/Proto/Tune.hs` defines the typed `TuneCommand` envelopes and
deterministic text render/parse round-trips for `StartSweep` and `StopSweep`;
`encodeTuneCommandProto` and `decodeTuneCommandProto` round-trip the current
command oneof through proto3-compatible bytes via `JitML.Proto.Wire`.
`encodeTuneEventProto` and `decodeTuneEventProto` round-trip the current
`TuneEvent` oneof through the same local wire helper. Generated cross-language
proto-lens output remains target work.

`TuneSweepLifecycle` GADT (`Sampled → Scheduled → Running → Pruned →
Reported → Finished`) is the typed lifecycle.

### Samplers

<!-- jitml:training.tune.samplers:start -->
| Constructor | Current scope |
|-------------|---------------|
| `Grid` | Generated from current Haskell catalog |
| `Sobol` | Generated from current Haskell catalog |
| `Random` | Generated from current Haskell catalog |
| `TPE` | Generated from current Haskell catalog |
| `GPBO` | Generated from current Haskell catalog |
| `GeneticAlgorithm` | Generated from current Haskell catalog |
| `NSGA2` | Generated from current Haskell catalog |
| `MuLambdaES` | Generated from current Haskell catalog |
| `CMAES` | Generated from current Haskell catalog |
| `EvolutionStrategies` | Generated from current Haskell catalog |
| `PBT` | Generated from current Haskell catalog |
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
deterministic key and resume-equality checks. `src/JitML/Tune/Resume.hs`
provides `persistTrialTranscript` and `replaySweep` over `HasMinIO`, validated
against the filesystem-backed instance; live HTTP MinIO persistence remains
target work. Sampler behaviour is exercised by `jitml-hyperparameter` as
properties (sampler state is a pure function of its seed and event log;
two runs produce bit-identical trial-spec sequences; `replaySweep` over a
recorded event log yields the same next-batch as the first-pass
dispatcher). Per-sampler `.txt` trial-value fixtures are explicitly
**not** committed — see [unit_testing_policy.md → Snapshot Tests and
the Prohibition on Numerical Fixtures](unit_testing_policy.md#snapshot-tests-and-the-prohibition-on-numerical-fixtures).

### `jitml tune` CLI

```
jitml tune <tune-dhall>
           [--resume <sweep-id>]
           [--dry-run | --plan-file <path>]
```

Current normal execution decodes the tuning Dhall, renders the selected
sampler/scheduler/pruner axes, and prints deterministic local trial values.
Target runtime work publishes `tune.command.<mode>` for the daemon's
at-least-once `TuneHandler`; the current proto mirror covers local text command
envelopes plus proto3-compatible byte envelopes for the command and event
oneofs.

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

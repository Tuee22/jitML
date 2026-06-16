# Training Workloads

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-8-supervised-and-rl-framework.md, ../../DEVELOPMENT_PLAN/phase-9-rl-catalog-alphazero-and-tuning.md, ../../DEVELOPMENT_PLAN/phase-13-no-caveat-model-runtime.md, ../../DEVELOPMENT_PLAN/phase-14-interactive-demo-and-playwright-closure.md, ../../DEVELOPMENT_PLAN/phase-18-no-caveat-product-handoff.md, checkpoint_format.md, numerical_core.md
**Generated sections**: training.rl.catalog, training.tune.samplers, training.tune.schedulers, training.tune.pruners

> **Purpose**: Project-specific training-workload doctrine for jitML — the
> current local SL summaries, RL metadata/framework surfaces, AlphaZero game
> helpers, and hyperparameter tuning catalogs, plus the reopened no-caveat
> runtime target for real train/eval/rollout/self-play/tune/checkpoint/inference
> workflows.

## SL Training Loops

`src/JitML/SL/` owns the supervised-learning surface. The current worktree has
the canonical problem catalog and all-row trainable product cohort in
`src/JitML/SL/Canonicals.hs`, typed dataset references in
`src/JitML/SL/Dataset.hs`, the single-hidden-layer softmax primitive in
`src/JitML/SL/Classifier.hs`, and the all-row substrate-backed architecture
runtime in `src/JitML/SL/Architecture.hs`.

- Current `Dataset.hs` renders pinned dataset object keys, maps them to bucket
  `jitml-datasets`, exposes `fetchDatasetRef` through the `HasMinIO`
  capability, and verifies fetched bytes against the pinned SHA-256. The
  filesystem-backed `HasMinIO` test covers the capability boundary; live
  routed MinIO fetch exists for the current MNIST artifact path and expands to
  every canonical dataset/model row under Sprint `8.12` / Phase `13`.

### Canonical SL Problems

The catalog is the full no-caveat architecture set. Sprint `8.12` adds
`JitML.SL.Canonicals.trainableCanonicalCohort`, which covers all eleven product
rows, and `JitML.SL.Architecture`, which maps those rows to trainable topologies
backed by the selected substrate `MlpDevice`. `denseMlpCohort` survives only as
a legacy compatibility helper for code that still names the older
single-hidden-layer Dense subset explicitly. The former deterministic synthetic
curve helpers were deleted; published training loss comes from live device
measurements.

| Current problem key | Owning module | Current validation |
|---------------------|---------------|--------------------|
| `mnist-shallow-mlp` | `src/JitML/SL/Architecture.hs` | Dense device topology; exercised by classifier convergence and all-row substrate train-step tests |
| `mnist-deep-mlp` | `src/JitML/SL/Architecture.hs` | DeepDense device stack; exercised by all-row substrate train-step tests |
| `mnist-lenet` | `src/JitML/SL/Architecture.hs` | Patch-convolution stem plus classifier; exercised by all-row substrate train-step tests |
| `fashion-mnist-mlp` | `src/JitML/SL/Architecture.hs` | Dense device topology; train-step covered, train/test image+label SHA pins present, live staged-byte smoke passed, convergence pending |
| `fashion-mnist-resnet` | `src/JitML/SL/Architecture.hs` | Residual device stack; train-step covered, train/test image+label SHA pins present, live staged-byte smoke passed, convergence pending |
| `cifar10-resnet20` | `src/JitML/SL/Architecture.hs`, `src/JitML/SL/Archive.hs` | 20-block residual device stack; train-step covered, CIFAR-10 binary archive SHA pin and archive-backed parser coverage present, live staged-byte smoke passed, convergence pending |
| `cifar10-resnet56` | `src/JitML/SL/Architecture.hs`, `src/JitML/SL/Archive.hs` | 56-block residual device stack; train-step covered, CIFAR-10 binary archive SHA pin and archive-backed parser coverage present, live staged-byte smoke passed, convergence pending |
| `cifar100-wide-resnet` | `src/JitML/SL/Architecture.hs`, `src/JitML/SL/Archive.hs` | Wide residual device stack; train-step covered, CIFAR-100 binary archive SHA pin and archive-backed parser coverage present, live staged-byte smoke passed, convergence pending |
| `cifar10-vit` | `src/JitML/SL/Architecture.hs`, `src/JitML/SL/Archive.hs` | Patch embedding plus trainable Q/K/V attention; train-step covered, CIFAR-10 binary archive SHA pin and archive-backed parser coverage present, live staged-byte smoke passed, convergence pending |
| `tiny-imagenet-resnet50` | `src/JitML/SL/Architecture.hs`, `src/JitML/SL/TinyImageNet.hs` | 50-block residual device stack; train-step covered, real archive SHA pin plus Zip64/JPEG tensor materialization present, live staged-byte smoke passed, convergence pending |
| `california-housing-mlp` | `src/JitML/SL/Architecture.hs`, `src/JitML/SL/Archive.hs`, `src/JitML/SL/Regression.hs` | Dense device topology; train-step covered, real archive SHA pin, archive-backed regression-row parser, standardized device-backed MSE trainer, and live staged-byte smoke present; convergence/checkpoint/inference closure pending |

Convergence is asserted statistically by `jitml-sl-canonicals`: the
median over a fixed-seed pool clears a sanity threshold derived from
the problem's literature target at test time. No per-substrate `.txt`
loss-curve fixtures are committed — see
[unit_testing_policy.md → Snapshot Tests and the Prohibition on
Numerical Fixtures](unit_testing_policy.md#snapshot-tests-and-the-prohibition-on-numerical-fixtures).
The live MNIST convergence case decodes the staged train/test IDX blobs and,
when a live publication exists, trains and evaluates through
`JitML.SL.Architecture.trainArchitectureWithDevice` /
`accuracyArchitectureWithDevice` on the selected `MlpDevice`; the linux-cpu
gate uses 60 full-batch device epochs at `1.0e-2` and leaves the in-code
threshold unchanged. The focused Sprint `8.12` live matrix now also fetches
staged bytes for every canonical row from live MinIO, materializes bounded
train/test examples, trains through the selected linux-cpu `MlpDevice`, and
verifies finite train/eval metrics. Phase `13` strengthens that staged-byte
smoke into median convergence, checkpoint reload, evaluation, and inference for
every canonical SL row.

### `jitml train` CLI

```
jitml train <experiment-dhall>
            [--resume <checkpoint-id>]
            [--dry-run | --plan-file <path>]
```

`jitml train` supports the Plan/Apply dry-run surface. On normal execution it
is **substrate-backed and fails closed** (Sprint 8.10): `JitML.App.runTrain`
delegates to `runDeviceMnistTraining`, which **requires** a live cluster
publication and a staged canonical dataset and otherwise exits with
`TrainingPrerequisiteUnmet` (exit 2) — printing and publishing nothing. There
is no synthetic summary and no pure-Haskell fallback: the staged dataset bytes
are decoded once through `JitML.SL.Classifier.decodeBoundedDataset`, the
experiment Dhall is resolved to a canonical row through
`JitML.SL.Canonicals.loadCanonicalProblemExperiment`, the row resolves to a
`JitML.SL.Architecture.ArchitectureSpec`, and
`JitML.SL.Architecture.trainArchitectureWithDevice` trains through the resolved
substrate's JIT-compiled `MlpDevice`, selected by
`mlpDeviceForSubstrate`. `jitml eval --checkpoint <id>` loads the
named inference checkpoint's `.jmw1` weights and runs the substrate-bound
weighted device forward; a missing pointer/manifest →
`InferenceCheckpointMissing`, and incompatible manifest experiment/content SHA
or tensor shape metadata fails closed before the runner is invoked. Sprint
`10.6` adds model-family architecture, preprocessing, output-decoder, and
weight-layout metadata to the checkpoint manifest consumed by this path.

The worker fetches `jitml-datasets/MNIST/{train,test}/{data,labels}.bin`, gunzips
(`JitML.SL.Dataset.maybeGunzip`), IDX-parses, and trains over the bytes —
example count / epochs / test size capped by the typed Dhall `RunConfig` so a
live run stays tractable. The worker decodes these caps from Dhall, not environment
variables: Phase `5` Sprint `5.7` retires the former `JITML_SL_TRAIN_LIMIT` /
`JITML_SL_EPOCHS` / `JITML_SL_TEST_LIMIT` env IPC in favour of the typed
`RunConfig` per the `Application Environment` doctrine (see
[Development Plan → Reopened phases](../../DEVELOPMENT_PLAN/README.md#reopened-phases-2026-05-29)). The measured `train_acc` / `test_acc` are reported and the published
`EpochCompleted` loss becomes the live measurement. The `jitml-sl-canonicals`
live MNIST assertion exercises the same architecture/device runtime when the
publication and staged bytes exist, so the test does not certify a separate
Dense-only path. Image + label blobs are
staged via `jitml internal upload-dataset --name MNIST --split <split>
--artifact {images,labels} --path <gz>`, SHA-verified against
`JitML.SL.Dataset.canonicalArtifactSha256For`. Fashion-MNIST now has the same
train/test image+label gzip SHA-pinned surface. CIFAR-10 and CIFAR-100 now use
`ArchiveArtifact` pins for the canonical Toronto binary tarballs, staged with
`--artifact archive`, and `JitML.SL.Classifier` parses extracted CIFAR binary
batch payloads into 3072-feature labeled examples through the shared
`JitML.SL.Archive` tar extractor. California Housing now uses an
`ArchiveArtifact` pin for `cal_housing.tgz`, and `JitML.SL.Regression` parses
`CaliforniaHousing/cal_housing.data` from the archive into eight-feature
regression examples with the raw target value; the runtime standardizes feature
columns and target values before training a one-output MSE regressor through the
selected `MlpDevice`. Tiny ImageNet now uses `JuicyPixels` plus a narrow
Zip64-aware central-directory reader to decode JPEG tensors from the pinned
archive.
`jitml train` routes staged CIFAR, Tiny ImageNet, and California archives
through these archive-backed decoders before training. Phase `13` wires
California checkpoint/inference plus a regression convergence gate, then
promotes the current all-row staged-byte smoke into median convergence for every
row before the all-row live convergence gate can close.
`src/JitML/Proto/Training.hs` defines the typed
`TrainingCommand` envelopes and deterministic text render/parse round-trips
for `StartTraining` and `StopTraining`; `encodeTrainingCommandProto` and
`decodeTrainingCommandProto` round-trip the current command oneof through
proto3-compatible bytes via `JitML.Proto.Wire`. `encodeTrainingEventProto`
and `decodeTrainingEventProto` round-trip the current `TrainingEvent` oneof,
including checkpoint metric entries, through the same local wire helper.
Generated cross-language proto-lens output remains target work. Sprint `8.12`
/ Phase `13` extend the runtime to resolve and SHA-hash every supported
experiment Dhall, reconcile prerequisites, materialize the dataset, publish
`StartTraining` on `training.command.<mode>`, consume `training.event.<mode>`
through the daemon, and persist checkpoints for every canonical model family.

## RL Framework Primitives

`src/JitML/RL/` owns the framework. Per doctrine `GADT-Indexed State
Machines`, the run lifecycle is the phase-indexed GADT
`RLRunLifecycle` in `src/JitML/RL/Framework.hs`. Its current data-kind
phases are `RLCollect → RLComputeAdvantages → RLOptimise → RLEvaluate →
RLCheckpoint`; `src/JitML/RL/Loop.hs` provides the deterministic local
`RLLoop` / `runRLLoop` surface, including deterministic rollout transition
capture into the local `ReplayBuffer`. The reopened no-caveat target brackets
this with live load/ready/serve/drain states and trained-policy artifacts for
every supported algorithm.

Current local surfaces live in `src/JitML/RL/Algorithms.hs`,
`src/JitML/RL/Environments.hs`, `src/JitML/RL/Framework.hs`, and
`src/JitML/RL/{Policy,VecEnv,Buffer,AsyncBuffer,Loop}.hs`, plus one module per
traditional algorithm under `src/JitML/RL/Algorithms/` and the AlphaZero
substack under `src/JitML/RL/AlphaZero/`. They provide deterministic catalog,
environment, run-plan, lifecycle, policy, buffer, loop, per-algorithm module,
canonical-game, MCTS, self-play, and arena helpers. Current device-backed paths
exist for the implemented workflow surface. Sprint `9.12` removes the
reward-derived algorithm-level projection helpers from canonical validation and
writes `.jmw1` checkpoints plus line-oriented replay artifacts from `jitml rl
train` / `jitml rl rollout`. Sprint `10.6` records RL policy model-family
metadata, policy-distribution output decoders, and replay/transcript pointers in
the checkpoint manifest. Phase `13` consumes those artifacts for the full product
matrix: every algorithm trains, evaluates, rolls out, checkpoints, and provides
browser replay/animation payloads.

### Algorithm Class Taxonomy (Type-Level)

The current `AlgorithmFamily` metadata in `src/JitML/RL/Algorithms.hs`
enumerates `OnPolicy`, `OffPolicy`, `Specialized`, and `SelfPlay`; the concrete
per-algorithm modules are aggregated by
`src/JitML/RL/Algorithms/Registry.hs`. The no-caveat runtime grows this into a
GADT-indexed `Algorithm` kind with traits:

- `OnPolicy` / `OffPolicy` / `Hierarchical` / `Recurrent`
- `MaskingCapable` (algorithm supports action masks)
- `ContinuousAction` / `DiscreteAction`
- `ImageObs` / `VectorObs`

The taxonomy is used at the type level to constrain algorithm-instance
declarations.

### Policy and Environment

- Current `Policy` carries typed policy metadata, parameter references, the
  substrate binding, and the substrate-bound `KernelHandle` model id; final
  runtime work loads and executes the referenced checkpointed policy for every
  algorithm-specific train/eval/rollout path.
- Current `RLEnvironment` metadata plus `VecEnv` combinator cover local
  deterministic stepping for native simulators. Default examples and required
  canonical tests use copyright-free environments only; `KeyDoorGrid-v0` is the
  active repo-owned visual discrete-control replacement for the former
  Atari-backed demo target.
- Current `src/JitML/RL/Environments.hs` provides local metadata and a
  deterministic step helper for cartpole, mountain-car, lunar-lander,
  `KeyDoorGrid-v0`, and the optional `atari-subset` row. `KeyDoorGrid-v0` is a
  deterministic seeded grid/key/locked-door environment with legal-action
  masks, vector/grid observations, generated render frames, and no external
  assets.
- `atari-subset` routes through `JitML.RL.ALE` only as optional runtime
  support. The project image may carry the pinned ALE library/runtime, but the
  repository no longer carries or compiles a checked-in C/C++ adapter shim. Any
  future project-owned ALE adapter must be generated by Haskell into the
  build/cache tree, or supplied explicitly outside the repository with
  `JITML_ALE_SHIM_PATH`. ROM bytes are never committed, baked into images, or
  required by default examples/tests. Optional Atari runs supply
  `RunConfig.atariRomPath`, `JITML_ATARI_ROM`, or `JITML_ALE_ROM`; without a
  ROM path, `atari-subset` fails with the explicit ROM-policy diagnostic.

### Buffers

- Current `ReplayBuffer` covers off-policy and on-policy rollout storage with
  deterministic sampling.
- Current `AsyncBuffer` provides the bounded async write discipline and drain
  boundary.
- Sprint `9.12` backs the async sink with live `HasMinIO` and adds the
  message-hash-deduplicated commit log so duplicates from the at-least-once
  Pulsar consumer are absorbed across all no-caveat RL workflows.

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

Sprint `9.12` splits these into dedicated modules where needed and composes
them into the no-caveat `RLLoop` closure.

### `jitml rl train` CLI

```
jitml rl train <rl-experiment-dhall>
               [--resume <checkpoint-id>]
               [--dry-run | --plan-file <path>]
```

Normal execution routes every MLP-backed trainer through the resolved
substrate's JIT device (Sprint 8.11): `JitML.App.runTrainerEpisodes` takes the
`rlDeviceForSubstrate`-selected `MlpDevice`, probes it once (`probeMlpDevice`)
and **fails closed** when the substrate toolchain/hardware is absent, then
dispatches the named trainer to its `*OnDevice` variant with iteration budgets
raised so training learns. **ARS is the lone no-MLP exception** (finite-difference
random search, no network forward/backward). The former `"simulator"` scripted
non-learning default is removed: `runRl` defaults the trainer to `ppo`, and an
unknown trainer → `InvalidConfig` with no episodes published.
PPO live convergence uses per-substrate tuning: `linux-cpu` uses 10 epochs per
update at `5.0e-4`; `linux-cuda` and `apple-silicon` use 8 epochs at `7.0e-4`.
`src/JitML/Proto/Rl.hs` defines the typed `RlCommand` envelopes and
deterministic text render/parse round-trips for `StartRLRun` and `StopRLRun`;
`encodeRlCommandProto` and `decodeRlCommandProto` round-trip the current
command oneof through proto3-compatible bytes via `JitML.Proto.Wire`.
`encodeRlEventProto` and `decodeRlEventProto` round-trip the current
`RlEvent` oneof, including `RlAnimationFrame` and `RlReplayFrame`, through the
same local wire helper. `JitML.RL.SimulatorLoop` records per-step
`SimulatedFrame` transitions from real environment dynamics, and the worker /
host publishers project those frames into typed animation events on
`rl.event.<mode>` when frames are available. Generated cross-language
proto-lens output remains target work. The no-caveat runtime publishes
`rl.command.<mode>` for the daemon's at-least-once `RlHandler` and requires the
browser replay surface to consume the same typed animation/replay payloads.

Placement is substrate-specific. Linux CPU/CUDA `rl.command.<mode>` messages may
become Kubernetes Jobs because the target device runtime is present in the worker
container. Apple Silicon `rl.command.apple-silicon` messages are public
orchestration commands only: the in-cluster daemon forwards Metal-backed RL
starts to `rl.host-command.apple-silicon` and the host daemon publishes normal
`rl.event.apple-silicon` events from the completed host run. Running the same
`jitml rl train` worker in a Linux pod for `apple-silicon` is not a valid
fallback; Phase `12` keeps the focused live no-Job assertion in the integration
suite, and Phase `16` validates the full Apple lane with no Metal-backed
workload Jobs.

`jitml rl eval --checkpoint <id>` shares `runCheckpointEval` with `jitml eval`
(Sprint 9.9): it loads the named checkpoint and runs the substrate-bound weighted
device forward, surfacing `InferenceCheckpointMissing` when absent — no echo
stub. `jitml rl rollout --seed N` runs one real on-device PPO rollout on cartpole
through `rlDeviceForSubstrate` (`runDeviceRollout`) and prints the measured
episode rewards, failing closed with `InvalidConfig` when the substrate device
is unavailable. The registered `moduleRolloutGenerator` surface now routes
through `JitML.RL.Algorithms.Common.trajectoryRollout`, which steps real named
environment dynamics with a deterministic seeded policy. The substrate-device
trained-policy rollout is validated on the live CUDA lane (`jitml rl rollout
experiments/cartpole.dhall --seed 42` printed measured CUDA rewards on
2026-06-11). Device-backed MCTS value-head leaf evaluation and device-backed
tuning trial training are implemented through the selected `MlpDevice` and fail
closed on device errors.

The same host-residency rule applies to supervised training, tuning trial
training, and AlphaZero value/policy evaluation whenever the selected substrate
is `apple-silicon`: Pulsar carries typed commands/events, MinIO carries datasets,
checkpoints, weights, and metrics, and only the host daemon calls the fixed Metal
bridge.

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
types at `dhall/rl/algos/<algo>.dhall`, trained-policy checkpoint loading, and
all-algorithm update/eval/rollout closure are Sprint `9.12` / Phase `13` work.
Per-algorithm trajectory `.txt` fixtures are explicitly
**not** committed — see [unit_testing_policy.md → Snapshot Tests and
the Prohibition on Numerical Fixtures](unit_testing_policy.md#snapshot-tests-and-the-prohibition-on-numerical-fixtures).

For off-policy algorithms, the bit-equality anchor is the first-N-
steps prefix per [determinism_contract.md → Same-Substrate Bit-Equality (RL
Caveat)](determinism_contract.md#same-substrate-bit-equality-rl-caveat),
again compared run-to-run rather than against a stored prefix.

## AlphaZero-Style Self-Play

The current AlphaZero surface lives in `src/JitML/RL/AlphaZero.hs` plus
`src/JitML/RL/AlphaZero/{Mcts,SelfPlay,PolicyValueNet}.hs`. It provides per-game
state/move helpers for Connect 4, Othello, Hex, and Gomoku, deterministic
transcript summaries, local game metadata, two-headed-network metadata,
persistent MCTS transposition-table helpers, self-play buffer hashing,
device-backed policy/value leaf evaluation, and arena-promotion measurement.
Sprint `9.12` adds shared terminal/winner/draw evaluators for every canonical
game and writes local `.jmw1` policy/value checkpoints from
`jitml rl alphazero self-play` together with a content-addressed
`alphazero-transcript` artifact carrying the sampled states, MCTS visit
distributions, and outcome labels consumed by replay/inspection surfaces. Sprint
`10.6` records AlphaZero policy/value model-family metadata, policy/value/MCTS
output decoders, and transcript pointers in the manifest. Phase `13` / `14`
still own full product-matrix consumption of those artifacts.

| Component | Current / target |
|-----------|------------------|
| Connect 4 helpers | Current: `src/JitML/RL/AlphaZero.hs` |
| Perfect-information game metadata | Current: `src/JitML/RL/AlphaZero.hs` |
| Two-headed network metadata | Current: `src/JitML/RL/AlphaZero.hs` |
| MCTS with PUCT and persistent tree state | Current recursive module: `src/JitML/RL/AlphaZero/Mcts.hs`; position-aware network prior/evaluator via `PolicyValueNet.netOracleFactory`; device-backed effectful leaf evaluation via `PolicyValueNet.netOracleFactoryWithDevice` / `mctsVisitDistributionWithDevice` |
| Self-play loop and replay buffer | Current module: `src/JitML/RL/AlphaZero/SelfPlay.hs`; `jitml rl alphazero self-play` emits checkpoint keys plus an `alphazero-transcript` artifact; Phase `13` / `14` consume those artifacts across every game/browser workflow |
| Arena gating | Current measured helper: `src/JitML/RL/AlphaZero/PolicyValueNet.hs` arena win-rate evaluation; terminal/winner/draw detection flows through `GameOutcome` for Connect 4, Othello, Hex, and Gomoku; the standalone `Arena` module is deleted |

### Persistent MCTS State

The top-level `MctsState` is a small local metadata record with visit count and
a prior seed. `JitML.RL.AlphaZero.Mcts` now provides the persistent
`TranspositionTable`, `TranspositionKey`, `runSearchWithTable`, and effectful
`runSearchWithPriorIO` helpers; the production self-play path uses the real
two-headed policy/value network evaluator instead of a deterministic prior.

### `jitml rl alphazero self-play` CLI

```
jitml rl alphazero self-play
                            [--substrate <substrate>]
                            [--seed <word64>]
                            [--games <n>]
                            [--sims <n>]
                            [--max-plies <n>]
                            [--updates <n>]
                            [--arena-games <n>]
```

The command probes the selected substrate `MlpDevice`, generates bounded
Connect 4 self-play samples through device-backed MCTS leaf policy/value
evaluation, trains the policy/value head on that device, and prints the sample
count plus arena win rate. A missing substrate runtime or device execution error
is an `InvalidConfig` failure; there is no pure-Haskell fallback on the CLI path.

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
the local tuning ADT, and renders a deterministic `jitml tune` plan. Trial
values are real local measured objectives (not LCG values). Live daemon-backed
trial persistence/replay is validated on the Linux lanes; substrate-device-backed
trial training is implemented by `trialObjectiveResultWithDevice` /
`deterministicTrialsWithDevice`, which train each measured trial through the
selected `MlpDevice`, return checkpointable trained weights for promotion, and
return a typed failure instead of falling back to a pure objective.
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

CLI Dhall overrides land in Sprint `1.12`: `jitml tune --sampler …
--scheduler … --pruner … --trials … --parallelism …` substitute on the
named axis only and never replace the surrounding `Tuning` record per
[../../README.md → Hyperparameter tuning, first-class](../../README.md#hyperparameter-tuning-first-class)
line 1050. The pure resolver
`JitML.Experiment.Overrides.applyOverrides` consumes `ParsedOption`
values, returning a typed `OverrideError` on invalid flag values that the
CLI boundary surfaces through the existing `AppError` /
`exitWithError` path. `jitml train` and `jitml rl train` accept the
analogous `--substrate` / `--seed` overrides for the experiment-Dhall
substrate and seed fields. See
[../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md → Sprint 1.12](../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md#sprint-112-cli-dhall-overrides-)
for the owning sprint and the doctrine-deviation interval recorded in
[../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md).

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
against the filesystem-backed instance; Sprint `9.12` / Phase `14` require live
HTTP MinIO persistence, checkpoint promotion, and browser-visible sweep state
for the no-caveat product workflow. Sampler behaviour is exercised by
`jitml-hyperparameter` as
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
sampler/scheduler/pruner axes, and executes measured trial objectives through
the selected device path where available. Sprint `9.12` writes the best local
trial's trained weights as a `.jmw1` checkpoint, emits a `tune-trials` artifact,
and promotes daemon-dispatched trial weights into `jitml-checkpoints` alongside
the `jitml-trials` transcript. Sprint `10.6` records tuning model-family
metadata, objective/regression output decoders, and trial transcript pointers in
the checkpoint manifest. Phase `14` publishes browser sweep
controls/frontier state over the daemon's at-least-once `TuneHandler`. The
current proto mirror covers local text command
envelopes plus proto3-compatible byte envelopes for the command and event
oneofs.

## Report-Card Measurements

`jitml test all --live` appends workload measurements to the typed
`JitML.Test.Report.ReportCard`: SL final loss, RL final reward, AlphaZero arena
win rate, and tuning best objective, plus daemon and cache fields owned by
the runtime and test surfaces. There is no cross-substrate parity field: the
determinism contract is within-substrate bit-for-bit only, and cross-substrate
equivalence is not asserted. Cache hit rate comes from the daemon's
`jitml_jit_cache_hits` / `jitml_jit_cache_misses` Prometheus counters on the
published `/metrics` edge route, and daemon health comes from the published
`/healthz` edge route. These values are telemetry from the current host or
cluster session. They are rendered as `unavailable` when a source is not
reachable and are never committed as numerical fixtures.

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
- [../../DEVELOPMENT_PLAN/phase-13-no-caveat-model-runtime.md](../../DEVELOPMENT_PLAN/phase-13-no-caveat-model-runtime.md)
- [../../DEVELOPMENT_PLAN/phase-14-interactive-demo-and-playwright-closure.md](../../DEVELOPMENT_PLAN/phase-14-interactive-demo-and-playwright-closure.md)

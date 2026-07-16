# Training Workloads

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-8-supervised-and-rl-framework.md, ../../DEVELOPMENT_PLAN/phase-9-rl-catalog-alphazero-and-tuning.md, ../../DEVELOPMENT_PLAN/phase-10-checkpointing-and-inference.md, ../../DEVELOPMENT_PLAN/phase-13-no-caveat-model-runtime.md, ../../DEVELOPMENT_PLAN/phase-14-interactive-demo-and-playwright-closure.md, ../../DEVELOPMENT_PLAN/phase-18-no-caveat-product-handoff.md, ../../DEVELOPMENT_PLAN/phase-22-canonical-matrix-and-dataset-integrity.md, ../../DEVELOPMENT_PLAN/phase-24-real-supervised-architectures.md, ../../DEVELOPMENT_PLAN/phase-25-real-rl-algorithms-and-environments.md, product_completion_contract.md, checkpoint_format.md, numerical_core.md, training_metrics_and_splits.md, run_contract.md
**Generated sections**: training.rl.catalog, training.tune.samplers, training.tune.schedulers, training.tune.pruners

> **Purpose**: Project-specific training-workload doctrine for jitML — the
> current local SL summaries, RL metadata/framework surfaces, AlphaZero game
> helpers, and hyperparameter tuning catalogs, plus the no-caveat runtime
> surface for real train/eval/rollout/self-play/tune/checkpoint/inference
> workflows.

Phase order, implementation status, blockers, and validation evidence live only
in the [Development Plan](../../DEVELOPMENT_PLAN/README.md). This document owns
workload-specific algorithms, environments, catalogs, and metric production.
The shared raw-plan, dimensional-budget, protocol, completion-evidence, and
live-interpreter boundary is
[Typed Run Contract](run_contract.md); the row-completion bar is
[Product Completion Contract](product_completion_contract.md).

Every product workload must project its verified data, measured update counters,
finite convergence measurements, terminal checkpoint, and domain-specific
artifacts into opaque `CompletedRunEvidence`. A primitive budget record,
declared metric, checkpoint pointer, or browser event cannot independently mint
completion or inference eligibility.

## SL Training Loops

`src/JitML/SL/` owns the supervised-learning surface. The current worktree has
the canonical problem catalog and all-row trainable product cohort in
`src/JitML/SL/Canonicals.hs`, typed dataset references in
`src/JitML/SL/Dataset.hs`, the single-hidden-layer softmax primitive in
`src/JitML/SL/Classifier.hs`, and the all-row substrate-backed architecture
runtime in `src/JitML/SL/Architecture.hs`. Phase `24` moved the executed
supervised architecture beyond that single-hidden-layer softmax primitive to a
real MLP-Mixer-style path — a token-mixing MLP plus executed LayerNorm — at
raised widths, so the trained topology matches the richer graph a product row
documents rather than an un-normalized dense stand-in.

- Current `Dataset.hs` renders pinned dataset object keys, maps them to bucket
  `jitml-datasets`, exposes `fetchDatasetRef` and
  `fetchVerifiedDatasetArtifactBytes` through the `HasMinIO` capability, and
  verifies fetched bytes against the pinned SHA-256 at the product read
  boundary. The filesystem-backed `HasMinIO` test covers the capability
  boundary; live routed MinIO fetch covers every canonical dataset/model row in
  the fixed-budget `linux-cpu` baseline.

### Canonical SL Problems

The catalog names the intended no-caveat architecture set. Phase `24` Sprint
`24.1` records each supervised row's claimed `ArchitectureFeature` values in
`ProductRow.rowArchitectureFeatures` and rejects any row whose literal
`archLayerGraph` lacks those features. A simplified trainable topology is still
useful implementation evidence, but it cannot close a row that documents a
richer architecture. The Phase `24` implementation closed the earlier
dense-stand-in gap: the deep and ViT rows train a real token-mixing MLP with an executed
LayerNorm (an MLP-Mixer block) at raised widths, so the executed model matches
the documented architecture instead of an un-normalized bag-of-patches dense
stand-in.

| Current problem key | Owning module | Current validation |
|---------------------|---------------|--------------------|
| `mnist-shallow-mlp` | `src/JitML/SL/Architecture.hs` | Dense device topology; fixed-budget convergence, checkpoint reload, and inference eligibility are validated in the `linux-cpu` baseline |
| `mnist-deep-mlp` | `src/JitML/SL/Architecture.hs` | Literal graph has Dense, two BatchNorm nodes, and two Dropout nodes; fixed-budget convergence, checkpoint reload, and inference eligibility remain later evidence gates |
| `mnist-lenet` | `src/JitML/SL/Architecture.hs` | Literal LeNet-style graph has two Conv2D nodes, pooling, and a classifier head; fixed-budget convergence, checkpoint reload, and inference eligibility remain later evidence gates |
| `fashion-mnist-mlp` | `src/JitML/SL/Architecture.hs` | Dense device topology; SHA pins plus fixed-budget convergence, checkpoint reload, and inference eligibility are validated in the `linux-cpu` baseline |
| `fashion-mnist-resnet` | `src/JitML/SL/Architecture.hs` | Literal small ResNet graph has Conv2D, BatchNorm, and two BasicBlock residual nodes; SHA pins and convergence evidence remain later gates |
| `cifar10-resnet20` | `src/JitML/SL/Architecture.hs`, `src/JitML/SL/Archive.hs` | Literal graph has Conv2D, BatchNorm, global pooling, and 20 BasicBlock residual nodes; archive parser evidence remains separate |
| `cifar10-resnet56` | `src/JitML/SL/Architecture.hs`, `src/JitML/SL/Archive.hs` | Literal graph has Conv2D, BatchNorm, global pooling, and 56 BasicBlock residual nodes; archive parser evidence remains separate |
| `cifar100-wide-resnet` | `src/JitML/SL/Architecture.hs`, `src/JitML/SL/Archive.hs` | Literal WideResNet-28-10 graph has Conv2D, GroupNorm, global pooling, and 12 wide BasicBlock residual nodes; archive parser evidence remains separate |
| `cifar10-vit` | `src/JitML/SL/Architecture.hs`, `src/JitML/SL/Archive.hs` | Literal small ViT graph has patch embedding, two LayerNorm nodes, MultiHeadAttention, GeGLU, token pooling, and a classifier head; the executed path uses a real token-mixing MLP + executed LayerNorm Mixer at raised widths rather than an un-normalized dense stand-in |
| `tiny-imagenet-resnet50` | `src/JitML/SL/Architecture.hs`, `src/JitML/SL/TinyImageNet.hs` | Literal ResNet-50 graph has Conv2D, BatchNorm, global pooling, and 16 BottleneckBlock residual nodes; archive SHA pin and Zip64/JPEG evidence remain separate |
| `california-housing-mlp` | `src/JitML/SL/Architecture.hs`, `src/JitML/SL/Archive.hs`, `src/JitML/SL/Regression.hs` | Dense regression topology; parser, device-MSE trainer, fixed-budget RMSE/MSE convergence, checkpoint reload, and inference eligibility are validated in the `linux-cpu` baseline |

Convergence is accepted only where the test performs the row's declared fixed
budget, verifies dataset bytes at the product read boundary, proves learned
state changed from initialization, and produces a `CompletedTraining` witness.
No per-substrate `.txt` loss-curve fixtures are committed — see
[unit_testing_policy.md → Snapshot Tests and the Prohibition on Numerical
Fixtures](unit_testing_policy.md#snapshot-tests-and-the-prohibition-on-numerical-fixtures).
All-row smoke or materialization coverage is not product closure.

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
`JitML.Experiment.Product.loadSupervisedProblemByPath`, the row resolves to a
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

Before any worker or host effect, `JitML.Plan.Command.prepareStartTraining`
refines the raw `StartTraining` fields into hidden `SupervisedPlan`. The plan's
positive, unit-indexed budget contains epochs, training examples, evaluation
examples, batch examples, and optimizer updates; refinement requires optimizer
updates to equal `epochs * ceil(trainingExamples / batchExamples)`. The
producer attaches the canonical version-`1` transport and content-derived
`PlanId`. Consumers run `validateStartTraining`, re-refining both the command
fields and the transport and requiring semantic, canonical-byte, and identity
equality.

Linux worker mounts use plan-only `TrainingRunConfig`: `planId`,
`resolvedPlan`, and the operational Pulsar WebSocket endpoint. The worker
parses and re-refines that transport before a Job launch, dataset read,
training update, checkpoint write, or event publication. It does not receive a
second primitive budget record, clamp a quantity, or reconstruct semantics from
environment defaults. The Apple host-command route validates the same
plan-bearing `StartTraining` command rather than creating a Linux-style mount,
so direct execution, daemon-dispatched Linux Jobs, and host Metal execution all
execute the same plan.

The worker fetches `jitml-datasets/MNIST/{train,test}/{data,labels}.bin`
through `JitML.SL.Dataset.fetchVerifiedDatasetArtifactBytes`, verifies the
canonical SHA-256 for each image/label object, then gunzips
(`JitML.SL.Dataset.maybeGunzip`), IDX-parses, and trains over the verified
bytes. Corrupt, substituted, truncated, or unpinned payloads fail closed as a
typed service error before decode. Example, epoch, and evaluation quantities
enter through the raw Dhall request and must refine to positive unit-indexed
values in the resolved `RunPlan`; the worker neither clamps them nor recovers
them from environment variables. Phase `5` Sprint `5.7` retired the former
`JITML_SL_TRAIN_LIMIT` / `JITML_SL_EPOCHS` / `JITML_SL_TEST_LIMIT` env IPC in
favour of the mounted run input per the `Application Environment` doctrine.
Sprint `5.17` keeps that mount fail-closed: a present but malformed
`/etc/jitml/run/RunConfig.dhall` exits as a typed configuration error instead of
falling back to env/default caps. The measured `train_acc` / `test_acc` are
reported and the published `EpochCompleted` loss becomes the live measurement.
The `jitml-sl-canonicals` live MNIST assertion exercises the same
architecture/device runtime when the publication and staged bytes exist, so the
test does not certify a separate Dense-only path. Image + label blobs are
staged via `jitml internal upload-dataset --name MNIST --split <split>
--artifact {images,labels} --path <gz>`, SHA-verified against
`JitML.SL.Dataset.canonicalArtifactSha256For` on upload and again on read.
Fashion-MNIST has the same train/test image+label gzip SHA-pinned surface.
CIFAR-10 and CIFAR-100 use `ArchiveArtifact` pins for the canonical Toronto
binary tarballs, staged with `--artifact archive`, verified on read, and parsed
by `JitML.SL.Classifier` from extracted CIFAR binary batch payloads into
3072-feature labeled examples through the shared `JitML.SL.Archive` tar
extractor. California Housing uses an `ArchiveArtifact` pin for
`cal_housing.tgz`; after read-time verification, `JitML.SL.Regression` parses
`CaliforniaHousing/cal_housing.data` from the archive into eight-feature
regression examples with the raw target value, and the runtime standardizes
feature columns and target values before training a one-output MSE regressor
through the selected `MlpDevice`. Tiny ImageNet uses `JuicyPixels` plus a narrow
Zip64-aware central-directory reader to decode JPEG tensors from the verified
pinned archive.
`jitml train` routes staged CIFAR, Tiny ImageNet, and California archives
through these archive-backed decoders before training. Successful supervised
training flattens the trained weights, writes a `.jmw1` checkpoint manifest
with PlanId-bound `CompletedTraining`, and records the read-time artifact digest
in `manifestDatasetShaAtRead`. Protocol publication distinguishes
`TrainingCheckpoint CheckpointDone`, an inspectable/resumable candidate with no
proof, from `TrainingCompletedCheckpoint CompletedCheckpointDone`, whose hidden
wrapper carries mandatory, re-refined completion. Completion metrics include
train loss, validation loss, held-out metric, and examples processed. Phase
`22` removes canonical-key synthetic live fixtures
from product workflow tests: product-row evidence uses real verified data or
fails closed before training. Phase `13` promotes the earlier all-row
staged-byte smoke into fixed-budget convergence, checkpoint reload, evaluation,
and inference for every row; that gate is closed for the `linux-cpu` baseline.
`src/JitML/Proto/Training.hs` defines the typed
`TrainingCommand` envelopes and deterministic text render/parse round-trips
for `StartTraining` and `StopTraining`; `encodeTrainingCommandProto` and
`decodeTrainingCommandProto` round-trip the current command oneof through
proto3-compatible bytes via `JitML.Proto.Wire`. `encodeTrainingEventProto`
and `decodeTrainingEventProto` round-trip the current `TrainingEvent` oneof,
including candidate and completed checkpoint variants, through the same local
wire helper. A completed nested payload first decodes as versioned
`RawCompletedTraining` and re-refines; generic protobuf/CBOR decoding does not
mint completion.
Generated proto-lens Haskell bindings live under `gen/Proto/Jitml/Training.hs`
and `gen/Proto/Jitml/Training_Fields.hs`. Sprint `8.12` / Phase `13` extend
the runtime to resolve and SHA-hash every supported
experiment Dhall, reconcile prerequisites, materialize the dataset, publish
`StartTraining` on `training.command.<mode>`, consume `training.event.<mode>`
through the daemon, and persist checkpoints for every canonical model family.

Product-row experiment resolution is centralized in
`JitML.Experiment.Product`. Every `ProductRow` `experimentConfig` either points
at a checked-in file under `experiments/` or is reflected from the typed product
registry into the same small Dhall record shape. The unit gate loads every
product row through that resolver, type-checks the resolved config, and fails on
missing files, malformed Dhall, unknown dataset/model keys, unknown
environment/game keys, or a generated PureScript/browser matrix constant that
has diverged from the Haskell registry.

The ProductRow publisher consumes the supervised epoch budget directly from
`JitML.Product.Matrix`: compact heavy-vision rows execute `5` epochs and the
remaining supervised rows execute `10`. The `sl_epochs=5` report-card knob
belongs to the canonical measurement stanza; it does not override a ProductRow
schedule and cannot produce ProductRow completion evidence.

Phase `12.16` aligns its live `StartTraining` integration request with the
existing registered/ProductRow-publisher MNIST schedule: **10** epochs ×
**7,000** training examples with **1,000** evaluation examples. The first
unfiltered pre-gate rerun had instead requested **5** epochs × **4,096**
training examples with **1,024** evaluation examples and produced
`test_accuracy = 0.8935546875`, below the unchanged **0.90** bar. The run
correctly could not mint `CompletedTraining` and timed out with incomplete
evidence; the test schedule was corrected without lowering the bar. The focused
live `StartTraining` case subsequently exited **0** and passed **1 / 1** in
**32.54s**, including cleanup. The full unfiltered pre-gate rerun remains open
while it runs.

## RL Framework Primitives

`src/JitML/RL/` owns the framework. `RLRunLifecycle` in
`src/JitML/RL/Framework.hs` indexes the legal computation phases
`RLCollect → RLComputeAdvantages → RLOptimise → RLEvaluate → RLCheckpoint`.
It is a domain projection into, not a replacement for, the placement/terminal/
evidence lifecycle in
[Typed Run Contract → Lifecycle State Machine](run_contract.md#lifecycle-state-machine).
`src/JitML/RL/EpisodeEnvelope.hs` provides the product projection type used by
trainer summaries, trajectory artifacts, animation frames, and `EpisodeDone`
publications. The deterministic `RLLoop` /
`runRLLoop` scaffold is test-support only under
`test/rl-canonicals/Support/Loop.hs`, where `scaffolding:`-prefixed tests keep
its historical determinism checks out of the product path.

Current local surfaces live in `src/JitML/RL/Algorithms.hs`,
`src/JitML/RL/Environments.hs`, `src/JitML/RL/Framework.hs`, and
`src/JitML/RL/{Policy,Buffer,AsyncBuffer,EpisodeEnvelope}.hs`, plus one module
per traditional algorithm under `src/JitML/RL/Algorithms/` and the AlphaZero
substack under `src/JitML/RL/AlphaZero/`. They provide catalog, environment,
run-plan, lifecycle, policy, buffer, per-algorithm module, canonical-game,
MCTS, self-play, arena, and publication-envelope helpers. Current device-backed paths
exist for the implemented workflow surface. Sprint `9.12` removes the
reward-derived algorithm-level projection helpers from canonical validation and
writes `.jmw1` checkpoints plus line-oriented replay artifacts from `jitml rl
train` / `jitml rl rollout`. Sprint `10.6` records RL policy model-family
metadata, policy-distribution output decoders, and replay/transcript pointers in
the checkpoint manifest. The product contract consumes those artifacts for the
full matrix: every algorithm must train for its fixed budget, evaluate,
roll out, checkpoint, publish convergence statistics, and provide browser
replay/animation payloads before it is treated as inference-eligible.

`JitML.RL.ProductBudget` is the shared planner for traditional RL ProductRow
training and completion. Its `2,000`-transition default is a requested floor,
not the completed budget: the registered row budget is the aggregate observed
environment-transition count after vector-environment multiplicity and the
trainer's indivisible rollout, fixed-step, ARS-direction, or HER-episode
granularity are applied. The producer executes that same schedule and completion
requires exact equality with its aggregate count. The separate
`rl_steps=100_000` report-card knob parameterizes canonical measurements and
cannot mint ProductRow completion.

### Algorithm Class Taxonomy (Type-Level)

The current `AlgorithmFamily` metadata in `src/JitML/RL/Algorithms.hs`
enumerates `OnPolicy`, `OffPolicy`, `Specialized`, and `SelfPlay`; the concrete
per-algorithm modules are aggregated by
`src/JitML/RL/Algorithms/Registry.hs`. Sprint `25.2` makes that registry carry
an `AlgorithmUpdateContract` per traditional product algorithm: a unique update
identity, trainer entry point, rollout surface, learned-artifact shape, and
update-feature list. `validateAlgorithmModuleRegistry` rejects duplicate
algorithm ids, duplicate update identities, and incomplete contracts, and the
product-row unit tests resolve every RL product algorithm through that registry.
The no-caveat runtime grows this into a GADT-indexed `Algorithm` kind with traits:

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
- Current `RLEnvironment` metadata plus `src/JitML/RL/Simulator.hs` cover native
  simulator dynamics. Default examples and required canonical tests use
  copyright-free environments only; `KeyDoorGrid-v0` is the active repo-owned
  visual discrete-control replacement for the former Atari-backed demo target.
- Current `src/JitML/RL/Environments.hs` provides local metadata for the seven
  product canonical environments: CartPole-v1, MountainCar-v0, Acrobot-v1,
  Pendulum-v1, LunarLander-v2 (discrete), KeyDoorGrid-v0, and
  GridWorld-Deterministic-v0. `src/JitML/RL/Simulator.hs` owns the native
  Haskell dynamics and render-frame projection for the same catalog; Pendulum
  remains a continuous-action environment with explicit torque bounds, with a
  discrete wrapper used only by generic test episode drivers. The old
  deterministic step helper is test-support only in
  `test/rl-canonicals/Support/DeterministicStep.hs`. `KeyDoorGrid-v0` is a
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
- The async sink persists through live `HasMinIO`; its commit log is keyed by
  the plan-bound semantic event ID so broker redelivery is idempotent without
  treating payload bytes as workflow identity.

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

Normal execution consumes a refined RL plan. Its training plan has distinct
environment-transition, rollout-per-environment, vector-environment, and
optimizer-update quantities; its evaluation plan has a non-empty seed cohort,
evaluation-episode count, and episode horizon. Only the pure plan compiler may
derive trainer iterations. It cannot use an evaluation count as a training
iteration count or an episode horizon as a rollout length. See
[Typed Plans and Dimensional Budgets](run_contract.md#typed-plans-and-dimensional-budgets).

Every MLP-backed algorithm resolves to the selected substrate's probed JIT
device and fails closed on device error. ARS is the explicit no-MLP exception
because it performs finite-difference policy search. Trainer selection is a
closed plan choice compatible with the algorithm and environment, not a second
text field that may disagree with the algorithm.

RL completion requires measured counters returned by the trainer, an exact
ordered iteration series whenever learning-curve properties are claimed, an
exact keyed final-policy evaluation cohort, finite rewards, the terminal metric,
and one completed checkpoint. Final-policy episodes are not training iterations,
and their delivery order is not a learning curve. The reducer and completion
shape are owned by
[Protocol and Evidence Contracts](run_contract.md#protocol-and-evidence-contracts).
`RlCheckpoint CheckpointDoneRL` records a candidate checkpoint;
`RlCompletedCheckpoint CompletedCheckpointDoneRL` is the distinct proof-bearing
variant with mandatory, re-refined `CompletedTraining`. Candidate persistence
alone cannot satisfy the reducer's completed-checkpoint requirement.

`src/JitML/Proto/Rl.hs` owns the raw versioned command/event codecs, including
animation and replay projections. Decoding or a text/protobuf round-trip does
not validate a run; decoded values refine against the `PlanId` and protocol
before the reducer can consume them. Generated proto-lens Haskell bindings live
under `gen/Proto/Jitml/Rl.hs` and `gen/Proto/Jitml/Rl_Fields.hs`.

Placement is substrate-specific. Linux CPU/CUDA `rl.command.<mode>` messages may
become Kubernetes Jobs because the target device runtime is present in the worker
container. Apple Silicon `rl.command.apple-silicon` messages are public
orchestration commands only: the in-cluster daemon forwards Metal-backed RL
starts to `rl.host-command.apple-silicon` and the host daemon publishes normal
`rl.event.apple-silicon` events from the completed host run. Running the same
`jitml rl train` worker in a Linux pod for `apple-silicon` is not a valid
fallback. The closed placement value and common interpreter make that host/
cluster distinction before publication or resource acquisition; see
[Lifecycle State Machine](run_contract.md#lifecycle-state-machine).

`jitml rl eval --checkpoint <id>` shares `runCheckpointEval` with `jitml eval`
(Sprint 9.9): it loads the named checkpoint and runs the substrate-bound weighted
device forward, surfacing `InferenceCheckpointMissing` when absent — no echo
stub. `jitml rl rollout --seed N` runs one real on-device PPO rollout on cartpole
through `rlDeviceForSubstrate` (`runDeviceRollout`) and prints the measured
episode rewards, failing closed with `InvalidConfig` when the substrate device
is unavailable. The trained-policy rollout surface steps real named environment
dynamics with deterministic seeded policy evaluation, not a catalog projection.
Device-backed MCTS value-head leaf evaluation and device-backed tuning trial
training are implemented through the selected `MlpDevice` and fail closed on
device errors. Sprint `8.15` applies that same typed fail-closed requirement to
post-probe off-policy/continuous trainer update failures: DQN, QR-DQN, HER, and
continuous actor-critic device trainers return `Left Text` for forward,
batch-gradient, and input-gradient faults, and `runTrainerEpisodes` stops the
run without bypassing the CLI/daemon error surface or publishing partial
episodes.

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
| `TRPO` | OnPolicy | no | 10 | `src/JitML/RL/Algorithms/Trpo.hs` |
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
aggregated by `Registry.algorithmModuleRegistry`; each module names the
algorithm-specific update contract that product rows must resolve before
training.
Related algorithms intentionally share a trainer family without sharing one
undifferentiated update rule. `trpo` and `recurrentppo` route through the PPO
on-policy family via
`PpoTrainer.Variant{TRPO,RecurrentPPO}` in `src/JitML/App.hs`, and `sac`,
`crossq`, and `tqc` route through
the continuous actor-critic family via
`ContinuousTrainer.Variant{SAC,CrossQ,TQC}` in the same module. Their distinct
logic includes a KL-constrained TRPO natural-gradient line search for every
rollout (TRPO ignores PPO's configured epoch count), RecurrentPPO recurrent
epochs, SAC entropy terms,
CrossQ target-net removal, and the TQC pooled-quantile critic. The Sprint `25.2`
collapse guard proves the named update paths do not collapse to identical final
parameters. Per-model convergence remains a separate evidence obligation; the
[`jitml-model-convergence` suite](../../DEVELOPMENT_PLAN/phase-33-per-model-convergence-and-inference-tests.md)
gates each algorithm/environment row on its own trained-policy convergence.
PPO/CartPole determinism is asserted by `jitml-rl-canonicals` as
run-to-run equality on the same substrate and seed (two fresh runs compared
against each other), and Sprint `25.2` adds a trained-parameter/update-path guard
for the on-policy variants so A2C, TRPO, and RecurrentPPO cannot collapse to
PPO's final parameters while MaskablePPO must carry the mask path through
rollout. Richer Dhall types at `dhall/rl/algos/<algo>.dhall`, trained-policy
checkpoint loading, and all-algorithm update/eval/rollout closure are
implemented for the `linux-cpu` baseline.
The TRPO device line search evaluates each candidate's full categorical policy
as one substrate-backed batch and fails closed on a device error. Each rollout
executes exactly one natural-gradient actor trust-region step, followed by ten
separate value-head-only critic passes over the configured rollout minibatches.
Each critic minibatch recomputes its gradient at the current critic parameters,
threads Adam with the TRPO-specific `value-learning-rate = 0.001`, and preserves
actor isolation. Neither count is derived from PPO epochs. Exact
applied-optimizer-step projection into `TrainingEvidence.updateCount` remains
reopened under Sprint `21.4`; a rollout count must not be presented as that
later proof. The runtime module, algorithm catalog, and trainer default agree
on `max-kl = 0.01`, ten CG iterations, `cg-damping = 0.1`,
`cg-residual-tol = 1e-10`, ten `0.8` backtracking candidates, ten critic passes,
and the `0.001` critic learning rate. The current implementation passes its
focused **17 / 17** scope and the full **517 / 517** `jitml-unit` stanza;
Fourmolu is clean for the changed scope and focused HLint reports no hints.
The container `jitml-rl-canonicals` lane with
`JITML_SUBSTRATE=linux-cpu` passes **40 / 40** in **225.43s**. These gates are
not ProductRow runtime convergence evidence. Phase `12.16`'s corrected
immutable-image rollout is complete at
`jitml:local@sha256:30eb596380d9e939ae5bd5e0a87757d557576ef7a32614e156953057eba8b813`:
all five application pods are Ready with zero restarts on config image ID
`sha256:560d1b72153a6d8acdf232facc986089c3a0a7f178cfb85627c2e25b34a0253a`.
An exact no-publish CartPole run then completed **1,228,800** transitions and
returned reward **500.0** in all **20** evaluation episodes, passing the
unchanged **185** bar. Lunar Lander completed **2,400,000** transitions and
returned **271.16021982** in all **20** evaluation episodes, passing the
unchanged **155** bar. The installed publisher then regenerated both rows with
**2** eligible, **0** unsupported, and **0** errors. Their focused artifact
slice passes **2 / 2**, and each row's local/live pointers and manifest content
SHAs agree. The installed immutable unfiltered `linux-cpu` producer subsequently
exited **0** after traversing all **55** ProductRows and reported **55** rows,
**55** eligible, **0** unsupported, and **0** errors; the corrected TRPO and
AlphaZero manifests were reproduced. The exact `integration.product` selection
then exited **0** and passed **55 / 55** in **0.01s**. The independent four-way
verifier also exited **0** with `canonical_rows=55`, `local_namespaces=55`,
`live_namespaces=55`, `local_pointers=55`, `live_pointers=55`,
`local_manifests=55`, `live_manifests=55`, `four_way_matches=55`, `missing=0`,
`extra=0`, `duplicates=0`, and `mismatches=0`. The unfiltered non-Live pre-gate
and full canonical validation gates remain open.
The ProductRow resolver explicitly tightens Lunar Lander to `max-kl = 0.002`;
Sprint `25.4` must project that environment-specific choice through the typed
traditional-RL plan rather than leaving it as an `App`-local override.
Sparse-goal on-policy product rows resolve
their count-exploration coefficient by variant and environment before the
generic zero fallback, so `MaskablePPO/key-door-grid` retains phase-aware
position/key/door novelty during training while deterministic evaluation uses
the learned masked policy without a reward bonus.
Per-algorithm trajectory `.txt` fixtures are explicitly
**not** committed — see [unit_testing_policy.md → Snapshot Tests and
the Prohibition on Numerical Fixtures](unit_testing_policy.md#snapshot-tests-and-the-prohibition-on-numerical-fixtures).

The convergence matrix for the catalog is model-owned, not family-owned. PPO,
A2C, TRPO, MaskablePPO, RecurrentPPO, DQN, QR-DQN, DDPG, TD3, SAC, CrossQ,
TQC, ARS, HER, and AlphaZero each require their own fixed budget, completed
training witness, convergence-statistics record, checkpoint, and UI/e2e
evidence. Family-level smoke tests do not close a model row.

The Phase `25` implementation runs these RL rollouts vectorized: roughly `16` parallel
environment instances are batched through the network in one device call per
step (reintroducing a real, product-reachable `JitML.RL.VecEnv`), and the RL
network hidden widths are raised (from `64`/`128` toward `~256`), so the
model-owned convergence bars above are re-cleared under the new vectorized
regime at the raised widths.

Phase `22` also registers the environment-floor parity rows `PPO/acrobot`,
`SAC/pendulum`, and `PPO/gridworld-deterministic` so every documented canonical
environment resolves to a product row rather than passing by representative
algorithm coverage alone. Those rows carry their own fixed budgets, convergence
bars, experiment configs, integration ids, and e2e ids in
`JitML.Product.Matrix`.

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
Every game oracle masks policy priors and visit targets to the exact legal move
set before MCTS expansion; self-play and arena opponents consume that same set,
so an illegal policy index is rejected rather than remapped to another action.
Othello represents a mandatory no-move turn with a deterministic pass marker,
normalizes that pass before policy evaluation, and backs values up according to
the actual player to move on each side of an edge.
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
Sprint `26.1` threads a transposition table through each self-play game's plies,
records per-ply cache-size evidence, applies deterministic root Dirichlet noise
from the supplied seed, and resolves equal PUCT scores by the lowest action
index.

### `jitml rl alphazero self-play` CLI

```
jitml rl alphazero self-play
                            [--substrate <substrate>]
                            [--seed <word64>]
                            [--game <connect4|othello|hex|gomoku>]
                            [--generations <n>]
                            [--games <n>]
                            [--sims <n>]
                            [--max-plies <n>]
                            [--updates <n>]
                            [--arena-games <n>]
```

The command probes the selected substrate `MlpDevice`, resolves the selected
game's initial state, observation size, and action count, generates bounded
self-play samples through device-backed MCTS leaf policy/value evaluation,
trains the policy/value head on that device, and prints the sample count plus
arena win rate. The written checkpoint records a `CompletedTraining` witness
with deterministic initial/final policy-value network hashes, a positive
self-play generation count, and the fixed-budget AlphaZero metric rows
`arena_win_rate`, `legal_move_rate`, `mcts_simulations_per_move`,
`self_play_games`, `self_play_generations`, and `self_play_samples`; the
checkpoint is inference-eligible only when the arena observation passes
`JitML.RL.ConvergenceThresholds.alphaZeroArenaThreshold`. When the command runs
in a worker context, the same completion publisher emits those rows through
Pulsar. A missing substrate runtime, unknown game, or device execution error is
an `InvalidConfig` failure; there is no pure-Haskell fallback on the CLI path.

Before any of those effects, `JitML.Plan.Command.prepareStartAlphaZeroRun`
refines the raw command into a hidden `AlphaZeroPlan`. Its positive quantities
separately index generations, self-play games, MCTS simulations per move,
maximum plies, optimizer updates, and arena games. The command carries the
canonical version-`1` plan transport and content-derived `PlanId`; the direct
path, daemon-dispatched Linux Job, and Apple host-command route all validate and
execute that same plan. The Linux `AlphaZeroRunConfig` mount contains only the
plan identity, resolved plan, and operational Pulsar WebSocket endpoint.
Missing, malformed, version-incompatible, non-canonical, or identity-mismatched
plan input fails before a game, checkpoint, or event publication.

`GenerationCompleted` and `ArenaCompleted` carry the plan identity.
`JitML.Run.WorkloadContract` requires the exact zero-based generation range,
the plan-prescribed self-play-game count in every generation, and exactly one
arena result with the plan-prescribed game count and a finite win rate. It
derives semantic event identity through the shared contract algebra, making an
identical delivery idempotent while rejecting gaps, out-of-range keys,
conflicting duplicates, wrong-plan events, and budget mismatches.

### Deterministic Stochasticity

Per-game RNG seeds derive from `splitmix64(experimentSeed, gameIndex)`. The
MCTS root-noise seed is derived from the per-game seed. Same-substrate same-
seed self-play produces bit-identical game sequences and visit counts for each
canonical game; the canonical test compares fresh reruns against each other and
does not check in transcript or visit-count fixtures.

### Canonical Adversarial Games

| Game | Owning module |
|------|---------------|
| Connect 4 | `src/JitML/RL/AlphaZero.hs` metadata, `initialConnect4`, `applyMove`, transcript helper, two-headed network, and `Masked Discrete(7)` action surface |
| Othello | `src/JitML/RL/AlphaZero.hs` metadata, `initialOthello`, exact legal-move application, deterministic forced-pass normalization, transcript helper, two-headed network, and `Masked Discrete(64)` action surface |
| Hex | `src/JitML/RL/AlphaZero.hs` metadata, `initialHex`, `hexApplyMove`, transcript helper, two-headed network, and `Masked Discrete(121)` action surface |
| Gomoku | `src/JitML/RL/AlphaZero.hs` metadata, `initialGomoku`, `gomokuApplyMove`, transcript helper, two-headed network, and `Masked Discrete(225)` action surface |

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
Sprint `9.15` keeps replay/resume total by recording `ResumeReadFailure` values
in `resumeReadFailures`: missing/read failures use `ResumeServiceFailure
ServiceError`, corrupt CBOR transcript bytes use `ResumeDecodeFailure Text`, and
`ResumeOutcome` `Eq` / `Show` remain total at the caller boundary. Sprint `9.16`
keeps the real-workflow rule strict: overrides that appear in CLI output are
applied before validation/artifact writing, and daemon-dispatched tuning workers
execute the sampler/scheduler/pruner already captured in their resolved
`TuningPlan` instead of re-reading primitive axis fields or enumerating the
whole catalog grid.
`jitml-hyperparameter` consumes the `tune_trials` and
`tune_budget_per_trial` report-card knobs from `cabal.project` for the local
TPE trial-budget assertion.
`src/JitML/Proto/Tune.hs` defines the typed `TuneCommand` envelopes and
deterministic text render/parse round-trips for `StartSweep` and `StopSweep`;
`encodeTuneCommandProto` and `decodeTuneCommandProto` round-trip the current
command oneof through proto3-compatible bytes via `JitML.Proto.Wire`.
`encodeTuneEventProto` and `decodeTuneEventProto` round-trip the current
`TuneEvent` oneof through the same local wire helper. That oneof separates
proof-free `TuneSweepFinished SweepFinished` from proof-bearing
`TuneSweepCompleted SweepCompleted`; the latter's hidden wrapper contains
mandatory, re-refined `CompletedTraining`. Generated proto-lens
Haskell bindings live under `gen/Proto/Jitml/Tune.hs` and
`gen/Proto/Jitml/Tune_Fields.hs`.

`TuneSweepLifecycle` indexes the domain computation phases (`Sampled →
Scheduled → Running → Pruned → Reported → Finished`). The complete tuning run
additionally uses the common placement, exact-trial evidence, terminal state,
settlement, and cleanup lifecycle in
[Typed Run Contract](run_contract.md).

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
substrate and seed fields, and `jitml rl train --algorithm <algorithm>` applies
an algorithm override to the resolved RL experiment without replacing the
surrounding environment/seed record. See
[../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md → Sprint 1.12](../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md#sprint-112-cli-dhall-overrides-)
for the owning sprint and the doctrine-deviation interval recorded in
[../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md).
When `--trials` lowers the trial count without an accompanying
`--parallelism`, the resolver caps the inherited Dhall parallelism at the new
trial count before plan refinement. An explicit `--parallelism` remains
authoritative: a value larger than the resolved trial budget is rejected as an
invalid plan instead of being silently changed.
Sprint `9.16` closes the tuning integration boundary: the resolved experiment,
including CLI overrides, is the only input to local tune artifacts; daemon
workers select trials from the versioned resolved `TuningPlan` and may not
silently replace its axes with a catalog-wide product. `TuneRunConfig` carries
only that canonical transport, its `PlanId`, and the Pulsar WebSocket endpoint.

`JitML.Plan.Command.prepareStartSweep` refines the overridden command once into
a hidden plan whose positive quantities distinguish trials, concurrent trials,
promotions, and per-trial optimizer updates. Local execution, Linux Jobs, and
the Apple host-command route all validate the same canonical plan and identity
before trial, checkpoint, or publication effects. Trials execute in cohorts no
wider than the resolved parallelism and each trains for the resolved update
count. Scheduler ranking and pruning retain a terminal disposition for every
trial; transcripts persist for all trials and only the exact resolved promotion
frontier receives checkpoints. `TrialStarted`, `TrialFinished`,
`SweepFinished`, and `SweepCompleted` carry the same `PlanId`.
`SweepFinished` reports exact completed, pruned, and promoted counts plus a
finite best objective, but remains proof-free. `SweepCompleted` wraps those
counts together with mandatory completion evidence.
`JitML.Run.WorkloadContract` accepts completion only for the exact zero-based
trial range plus exactly one proof-bearing sweep result, with finite objectives
and the plan-prescribed completed-trial and promoted-trial counts. Identical
semantic redeliveries are idempotent; gaps, out-of-range keys, wrong-plan events,
conflicting duplicates, budget mismatches, and non-finite objectives are typed
violations.

The registered `hyperparameter-tuning` ProductRow is also the live integration
schedule; the test does not substitute a two-trial smoke fixture. It resolves
`TPE` + `ASHA` + `MedianPruner`, **128 trials**, sweep seed **1729**, **6**
optimizer updates per trial, and parallelism **1** from the ProductRow,
`experiments/mnist-tune.dhall`, and the named `JitML.Tune.Catalog` defaults.
The unchanged convergence contract maximises `best_objective` against target
**1.0** with slack **0.05**, and is checked over the best promoted measured
objective. A non-live integration regression loads and executes the same
registered schedule through sampling, scheduling, pruning, promotion, and bar
evaluation so fixture drift fails before the live workflow is launched.

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

Target normal execution decodes the tuning Dhall, applies CLI overrides before
validation, renders the selected sampler/scheduler/pruner axes from the resolved
experiment, and executes measured trial objectives through the selected device
path where available. Sprint `9.12` writes the best local
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

`jitml test all --live` derives workload measurements from the typed journals
produced by the scenarios that actually ran: SL held-out loss, RL final-policy
evaluation return, AlphaZero arena win rate, and tuning best objective, plus
daemon/cache observations recorded in those journals. Reporting never launches
a second measurement workflow or substitutes a fixture. `NotRequested`,
`Unavailable reason`, and `Available evidence` are distinct states. See
[Evidence Journals and Reporting](run_contract.md#evidence-journals-and-reporting).

There is no cross-substrate parity field: the determinism contract is
within-substrate bit-for-bit only, and cross-substrate equivalence is not
asserted. Numerical values are never committed as fixtures.

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
- [run_contract.md](run_contract.md)
- [../../DEVELOPMENT_PLAN/phase-8-supervised-and-rl-framework.md](../../DEVELOPMENT_PLAN/phase-8-supervised-and-rl-framework.md)
- [../../DEVELOPMENT_PLAN/phase-9-rl-catalog-alphazero-and-tuning.md](../../DEVELOPMENT_PLAN/phase-9-rl-catalog-alphazero-and-tuning.md)
- [../../DEVELOPMENT_PLAN/phase-13-no-caveat-model-runtime.md](../../DEVELOPMENT_PLAN/phase-13-no-caveat-model-runtime.md)
- [../../DEVELOPMENT_PLAN/phase-14-interactive-demo-and-playwright-closure.md](../../DEVELOPMENT_PLAN/phase-14-interactive-demo-and-playwright-closure.md)

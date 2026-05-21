# Phase 8: Supervised Learning and RL Framework

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-6-numerical-core.md](phase-6-numerical-core.md),
[phase-7-jit-codegen-and-substrates.md](phase-7-jit-codegen-and-substrates.md),
[phase-9-rl-catalog-alphazero-and-tuning.md](phase-9-rl-catalog-alphazero-and-tuning.md),
[../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Own the SL canonical summaries, RL catalog/environment
> metadata, deterministic trajectory helpers, command summaries, run-plan
> metadata, and the three GADT-indexed lifecycles. Daemon-backed training
> loops, real datasets, buffers, callbacks, GAE, target networks, and
> live Pulsar events are tracked in the per-sprint `### Remaining Work`
> blocks below.

## Phase Status

🔄 **Active**. The phase owns the framework half of
[Exit Definition](README.md#exit-definition) item 6 (`jitml train` and
`jitml rl train` run the full SL/RL workloads, with golden tests for SL
convergence and RL trajectories under `jitml test all`). **Met today**:
Sprint `8.5` closed the typed framework metadata catalog (schedules,
action distributions, action noise, target networks, GAE, callbacks,
evaluator); Sprint `8.7` closed the `RLRunLifecycle` GADT retrofit.
The typed dataset surface (`src/JitML/SL/Dataset.hs`), the deterministic
SL training pipeline (`src/JitML/SL/{Loop,Train}.hs`), the runtime RL
primitives (`src/JitML/RL/{Policy,VecEnv,Buffer,Loop}.hs`), the
`training` / `rl` / `tune` proto files (`proto/jitml/*.proto`), and
their typed Haskell envelopes (`src/JitML/Proto/{Training,Rl,Tune}.hs`)
are checked in; `TrainingCommand` and `RlCommand` now have deterministic
text render/parse round-trips for the current command envelopes. **Unmet
today**: Sprints `8.1`–`8.6` still owe the
live MinIO dataset fetch through the available `HasMinIO` client, the live
Pulsar publish/consume round-trip through a real `HasPulsar` client, generated protobuf
serialization (proto-lens output), and the live convergence / reward
golden fixtures against real hardware. Detailed remaining work lives in
each sprint's `### Remaining Work` block below.

### Current Implementation Scope

The worktree implements deterministic catalog summaries: eleven canonical
SL problem cells with synthetic convergence curves in
`src/JitML/SL/Canonicals.hs`; the `jitml train` / `jitml eval` command
summaries; the RL command summaries; and deterministic trajectory helpers
in `src/JitML/RL/Algorithms.hs`. The typed pipeline surfaces in
`src/JitML/SL/{Dataset,Loop,Train}.hs` and `src/JitML/RL/{Policy,VecEnv,Buffer,Loop}.hs`
implement deterministic-fixture-producing training loops, replay
buffers with deterministic insertion/sample ordering, a typed `Policy`
carrying the substrate-bound `KernelHandle` model id, and a `VecEnv`
that parallel-steps the existing canonical environments. The proto
surfaces (`proto/jitml/{training,rl,tune}.proto` + typed envelopes in
`src/JitML/Proto/{Training,Rl,Tune}.hs`) define the substrate-scoped
Pulsar command / event topic family; the training and RL command modules
also parse the deterministic local text envelope emitted by their renderers.
Live MinIO dataset fetch, live
Pulsar publish/consume, and real-hardware convergence assertions are
the open work in the per-sprint `### Remaining Work` blocks below.

## Phase Summary

This phase delivers SL plus the RL *framework*. Phase `9` builds on
these primitives to deliver the algorithm catalog (14 traditional RL
algorithms plus AlphaZero), the AlphaZero self-play stack, and the
hyperparameter tuner. Splitting the work this way lets RL framework
changes settle before the algorithm implementations consume them.

## Sprint 8.1: Local Supervised Canonical Summaries 🔄

**Status**: Active
**Implementation**: `src/JitML/SL/Canonicals.hs`,
`test/sl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Stand up the current deterministic supervised-learning catalog summary. Real
dataset loaders, daemon-backed training loops, MinIO dataset access, live
convergence thresholds, and committed golden curve fixtures remain target
runtime work.

### Deliverables

- `src/JitML/SL/Canonicals.hs` declares the eleven current canonical cells:
  `mnist-shallow-mlp`, `mnist-deep-mlp`, `mnist-lenet`,
  `fashion-mnist-mlp`, `fashion-mnist-resnet`, `cifar10-resnet20`,
  `cifar10-resnet56`, `cifar100-wide-resnet`, `cifar10-vit`,
  `tiny-imagenet-resnet50`, and `california-housing-mlp`.
- `convergenceCurve` produces a five-point deterministic synthetic loss curve
  from the problem seed.
- `finalLoss` returns the final value from that deterministic curve.
- `test/sl-canonicals/Main.hs` verifies the catalog is populated, curves are
  deterministic, and every final loss improves over the initial loss.
- `src/JitML/SL/Dataset.hs` declares the typed `DatasetRef` / `DatasetSplit`
  surface, the `canonicalDatasets` registry covering MNIST,
  Fashion-MNIST, CIFAR-10, CIFAR-100, Tiny ImageNet, and California
  Housing, the deterministic `expectedSha256` derivation,
  `datasetObjectRef`, `verifyDatasetBytes`, and `fetchDatasetRef` through
  the `HasMinIO` capability boundary.
- `src/JitML/SL/Loop.hs` declares `LoopConfig`, `EpochOutcome`, and
  `TrainPipeline`, threading the deterministic convergence curve from
  Sprint 8.1 through the `TrainingLifecycle` GADT singletons.
- `src/JitML/SL/Train.hs` declares `TrainingConfig`, `TrainResult`,
  and `train :: TrainingConfig -> ReaderT Env m TrainResult`, computing
  the per-dataset convergence threshold and the `converged` flag from
  the deterministic pipeline final loss.
- Live Pulsar training events backed by real `HasPulsar` and real
  MinIO-staged datasets remain target work owned by Sprint 5.4 / 5.5 /
  4.3 / 4.4 once the cluster is up.

### Validation

1. `cabal test jitml-sl-canonicals` exercises the eleven-cell canonical
   summary body and the deterministic `TrainingConfig` convergence pipeline.
2. `jitml train experiments/mnist.dhall` renders the deterministic
   summary from `src/JitML/App.hs`.
3. Live validation (target): a real training run against MNIST hits the
   canonical convergence threshold, the trained checkpoint round-trips,
   and the live measured golden curve under
   `test/golden/sl/<problem-key>/` matches bit-for-bit on the
   determinism-contract substrate.

### Remaining Work

- `JitML.SL.Dataset.fetchDatasetRef` now reads dataset bytes through
  `HasMinIO`, maps the object to bucket `jitml-datasets`, and verifies the
  SHA-256 before returning a typed `DatasetFetchResult`; `jitml-sl-canonicals`
  validates the path against the filesystem-backed `HasMinIO` instance.
  Remaining live work is wiring this function into `jitml train` /
  `TrainingHandler` with `JitML.Service.MinIOSubprocess`, the routed live
  MinIO client from Sprint 4.3, and replacing local fixture hashes with real
  dataset object hashes from experiment Dhall.
- Replace or supplement the current deterministic synthetic fixtures under
  `test/golden/sl/<problem-key>/` with live measured convergence fixtures
  once the daemon-backed training loop runs on real hardware against real
  datasets.
- Add the live SL convergence assertion to `jitml-sl-canonicals` (Sprint
  `12.3`) once the live MinIO + live cluster path is up.

## Sprint 8.2: `jitml train` Local CLI Summary 🔄

**Status**: Active
**Implementation**: `src/JitML/App.hs`, `src/JitML/Plan/Plan.hs`,
`src/JitML/Proto/Training.hs`
**Docs to update**: `documents/engineering/training_workloads.md`,
`documents/engineering/daemon_architecture.md`

### Objective

Wire `jitml train` into the CLI as a Plan/Apply-capable command with a current
local summary body. Pulsar command/event publication remains target daemon work.

### Deliverables

- `jitml train <experiment-dhall>` is registered in `CommandSpec`.
- `jitml train --dry-run <experiment-dhall>` renders the generic training plan
  through `src/JitML/Plan/Plan.hs`.
- Normal `jitml train` execution prints the selected experiment path, the first
  local canonical problem, and its deterministic final loss.
- `src/JitML/Service/Consumer.hs` provides the local at-least-once
  deduplication helper used by later event-flow work.
- `proto/jitml/training.proto` declares `StartTraining`, `StopTraining`,
  `EpochCompleted`, `CheckpointDone`, `TrainingFailed` plus
  discriminated `TrainingCommand` / `TrainingEvent` unions for the
  substrate-scoped Pulsar topics. `src/JitML/Proto/Training.hs` mirrors
  the proto into typed Haskell envelopes with deterministic renderers and
  `parseTrainingCommand` for the current text command envelopes.
  `trainingCommandTopic` / `trainingEventTopic` resolve the
  substrate-scoped topic names.
- The GADT-indexed `TrainingLifecycle` already lives in
  `src/JitML/RL/Framework.hs` (Sprint 8.4 / 8.7); the pipeline in
  `src/JitML/SL/Loop.hs` walks the singleton lifecycle.
- `proto-lens`-generated Haskell bindings for wire-format serialization
  remain to be added when the `proto-lens-protoc` dependency lands.

### Validation

1. `jitml train --dry-run experiments/mnist.dhall` emits the typed plan
   and exits `0`.
2. `jitml train experiments/mnist.dhall` prints the deterministic
   canonical-problem summary.
3. `cabal test jitml-sl-canonicals` covers render/parse round-trips for
   `StartTraining` and `StopTraining` text command envelopes.
4. Live validation (target): `jitml train` resolves and SHA-hashes the
   experiment Dhall, reconciles prerequisites, materializes the dataset,
   publishes `StartTraining` on `training.command.<mode>`, the daemon's
   `TrainingHandler` consumes it, and the resulting
   `training.event.<mode>` envelopes drive the report card.

### Remaining Work

- Generate wire-format protobuf bindings via `proto-lens-protoc` (or
  equivalent) so the typed envelopes in `src/JitML/Proto/Training.hs`
  round-trip with binary equivalence. The current parser is only for the
  local deterministic text envelope used by tests and future daemon-handler
  scaffolding.
- Implement the daemon-side `TrainingHandler` that consumes
  `training.command.<mode>` and publishes `training.event.<mode>` through
  the `RetryPolicy` boundary against a live Pulsar broker.
- Add the integration test that exercises one real publish → consume
  round-trip on the explicit live validation path.

## Sprint 8.3: RL Catalog Hook for Canonical Tests 🔄

**Status**: Active
**Implementation**: `src/JitML/RL/Algorithms.hs`,
`src/JitML/RL/Environments.hs`,
`test/rl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Land the RL catalog and canonical environment hook used by the
canonical RL stanza.

### Deliverables

- `src/JitML/RL/Algorithms.hs` declares the algorithm catalog consumed by the
  current `jitml-rl-canonicals` stanza.
- `deterministicTrajectory` provides a fixed-seed integer trajectory helper for
  local determinism tests.
- `test/rl-canonicals/Main.hs` verifies representative catalog entries and the
  deterministic trajectory helper.
- `src/JitML/RL/Environments.hs` declares the local canonical environment
  catalog for `cartpole`, `mountain-car`, `lunar-lander`, and `atari-subset`,
  plus a deterministic local step helper.
- `src/JitML/RL/VecEnv.hs` declares `VecEnv` and `vecEnvStep`, which
  fan the existing deterministic per-environment step helper across N
  parallel replicas with per-replica seed offsets.
- Full simulator bindings (real cartpole physics, real lunar-lander
  Box2D physics, ALE atari-subset bindings) and render-frame access
  remain target runtime work.

### Validation

1. `cabal test jitml-rl-canonicals` exercises the catalog and the
   deterministic trajectory helper.
2. `jitml-unit` verifies the canonical environment catalog and
   deterministic step helper.
3. Live validation (target): real cartpole / mountain-car / lunar-lander
   / atari-subset environments step under the daemon-backed env loop,
   render frames on request, and reproduce the per-seed trajectory
   determinism that the deterministic helper today only models.

### Remaining Work

- Implement real simulator bindings for cartpole, mountain-car,
  lunar-lander, and atari-subset (e.g., via `inline-c`, an embedded
  Box2D, and ALE).
- Implement the typed env-step boundary (`step :: Env -> Action -> IO
  (Obs, Reward, Done)`) plus render-frame access.
- Implement the daemon-backed environment loop driven by Sprint `5.5`'s
  Pulsar consumer.

## Sprint 8.4: RL Metadata Primitives 🔄

**Status**: Active
**Implementation**: `src/JitML/RL/Algorithms.hs`,
`src/JitML/RL/Framework.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Stand up the local metadata primitives consumed by the Phase `9` algorithm
catalog and the GADT-indexed lifecycle surfaces required by the doctrine.

### Deliverables

- `AlgorithmFamily` enumerates `OnPolicy`, `OffPolicy`, `Specialized`, and
  `SelfPlay`.
- `RLAlgorithm` records `algorithmName`, `algorithmFamily`, and
  `algorithmReplayBased`.
- `algorithmCatalog` contains the metadata rows consumed by the
  CLI and tests.
- `src/JitML/RL/Framework.hs` defines the local `TrainingLifecycle`,
  `TuneSweepLifecycle`, and (after Sprint 8.7) `RLRunLifecycle` GADT
  lifecycle surfaces plus the matching `rlRunPlan`.
- `src/JitML/RL/Policy.hs` declares the runtime `Policy` record with
  `PolicyShape`, `ParamRef` references, the substrate binding, and the
  `KernelHandle` model id.
- `src/JitML/RL/VecEnv.hs` provides parallel environment stepping
  (`VecEnv`, `vecEnvStep`, `vecEnvTrajectory`).
- `src/JitML/RL/Buffer.hs` provides the `ReplayBuffer` with
  deterministic insertion + sample ordering, supporting both
  `OnPolicyRollout` and `OffPolicyReplay` modes.
- `JitML.RL.AsyncBuffer` provides the typed `AsyncBuffer` /
  `AsyncSink` wrapper around `ReplayBuffer`: `insertAsync` updates the
  buffer in-place and spawns an async write through the sink, while
  `drainAsync` waits for pending writes at episode-end / drain boundaries.
  `jitml-unit` covers deterministic in-order drain behaviour and
  `jitml-integration` covers a filesystem-backed `HasMinIO` sink.

### Validation

1. `cabal test jitml-rl-canonicals` verifies the algorithm catalog
   contains representative expected algorithms.
2. `jitml-unit` verifies the run-plan rendering.
3. Live validation (target): real `Policy`, `VecEnv`, replay/rollout
   buffers, and `Async` write discipline are exercised end-to-end against
   running environments through the daemon.

### Remaining Work

- Wire the `AsyncSink` contract to the live HTTP-backed `HasMinIO`
  client and the daemon-backed RL loop once Sprint `5.4` lands the live
  object-store client.

## Sprint 8.5: RL CLI Summaries and Report Hooks 🔄

**Status**: Active
**Implementation**: `src/JitML/RL/Algorithms.hs`,
`src/JitML/RL/Framework.hs`, `src/JitML/Proto/Rl.hs`,
`src/JitML/Test/Report.hs`, `src/JitML/App.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Wire the current RL CLI summaries, framework metadata, and report-card hooks.

### Deliverables

- `jitml rl train <rl-experiment-dhall>` is registered as a Plan/Apply-capable
  command and prints the selected experiment plus the local algorithm count
  during normal execution.
- `jitml rl eval --checkpoint <id>` prints the selected checkpoint.
- `jitml rl rollout --seed <n>` prints the deterministic local trajectory from
  `deterministicTrajectory`.
- `src/JitML/Test/Report.hs` carries the report-card stanza list used by the
  current test summary.
- `src/JitML/RL/Framework.hs` declares schedules, action distributions, action
  noise, target networks, GAE, callbacks, and evaluator metadata.
- `proto/jitml/rl.proto` declares `StartRLRun`, `StopRLRun`,
  `EpisodeDone`, `EvalDone`, `CheckpointDoneRL`, `MetricUpdate` plus
  the discriminated `RlCommand` / `RlEvent` unions for the
  substrate-scoped topics. `src/JitML/Proto/Rl.hs` mirrors the proto
  into typed envelopes, including `parseRlCommand` for the current text
  command envelope; `rlCommandTopic` / `rlEventTopic` resolve the topic
  names per substrate.
- Live Pulsar codecs that serialize the typed envelopes to wire format
  remain to be added when proto-lens-protoc lands.

### Validation

1. `jitml rl train --dry-run experiments/cartpole.dhall` emits the typed
   plan.
2. `jitml rl rollout --seed 42` prints a deterministic trajectory.
3. `jitml-unit` verifies the framework catalog and run-plan surface.
4. `cabal test jitml-rl-canonicals` covers render/parse round-trips for
   `StartRLRun` and `StopRLRun` text command envelopes.
5. Live validation (target): `jitml rl train` publishes `StartRLRun` on
   `rl.command.<mode>`; the daemon's `RlHandler` consumes it, runs the
   real RL loop, and publishes `rl.event.<mode>` envelopes
   (`EpisodeDone`, `EvalDone`, `CheckpointDone`, `MetricUpdate`) that
   round-trip into the report card.

### Remaining Work

- Generate `proto-lens` Haskell wire bindings to round-trip the
  envelopes binary-equivalent to other-language clients. The current
  `parseRlCommand` implementation is only the deterministic local text
  envelope parser.
- Implement the daemon-side `RlHandler` that consumes
  `rl.command.<mode>` and emits `rl.event.<mode>` through the
  `RetryPolicy` boundary against a live broker (owned by Sprint 5.5).
- Add the live integration test that round-trips one `StartRLRun` →
  `EpisodeDone` cycle on the explicit live validation path.

## Sprint 8.6: RL Training Plan Surface 🔄

**Status**: Active
**Implementation**: `src/JitML/App.hs`, `src/JitML/Plan/Plan.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Expose the current RL training plan surface. Real typed RL training pipelines
remain target runtime work.

### Deliverables

- `src/JitML/Plan/Plan.hs` renders the current `jitml rl train` plan steps.
- `src/JitML/App.hs` dispatches `jitml rl train`, `jitml rl eval`, and
  `jitml rl rollout` to local summaries.
- `src/JitML/Service/Consumer.hs` provides the payload-hash deduplication
  helper for later RL event consumers.
- `src/JitML/RL/Loop.hs` declares `RLLoop`, `RLConfig`, `EpisodeResult`,
  and `RLLoopResult`. `runRLLoop` walks the algorithm × policy ×
  environment cohort through the `RLRunPhase` plan, accumulating
  per-episode rewards from the deterministic environment step helper
  and recording the rollout in a typed `ReplayBuffer`.
- Daemon-backed training execution against live Pulsar / live MinIO
  remains target runtime work.

### Validation

1. `jitml rl train --dry-run experiments/cartpole.dhall` emits the typed
   plan.
2. `jitml rl train experiments/cartpole.dhall` prints the algorithm
   catalog summary.
3. `cabal test jitml-rl-canonicals` verifies the deterministic local
   `RLLoop` records rollout transitions into its `ReplayBuffer`.
4. Live validation (target): a real `RLLoop` executes against the daemon
   for one cartpole episode, reaches the reward threshold, and the
   resulting checkpoint resumes bit-deterministically to the same reward.

### Remaining Work

- Plumb the typed `RL.Loop.runRLLoop` through the daemon's `RlHandler`
  and verify it consumes the per-domain dedup cache, checkpoints to
  MinIO, and emits live `rl.event.<mode>` envelopes. The typed loop
  surface is in place; the live broker + capability classes remain
  owned by Sprint 5.4 / 5.5.
- Add the live reward-threshold + checkpoint/resume equality assertion to
  `jitml-rl-canonicals` (Sprint `12.4`).

## Sprint 8.7: `RLRunLifecycle` GADT Retrofit ✅

**Status**: Done
**Implementation**: `src/JitML/RL/Framework.hs`, `test/unit/Main.hs`
**Docs to update**: `system-components.md`, `legacy-tracking-for-deletion.md`

### Objective

Retire the flat `RunPhase` enum and replace it with the phase-indexed
`RLRunLifecycle` GADT prescribed by doctrine `§ GADT-Indexed State Machines`,
so all three jitML lifecycles (`TrainingLifecycle`, `RLRunLifecycle`,
`TuneSweepLifecycle`) share the same singleton-witness shape.

### Deliverables

- `src/JitML/RL/Framework.hs` declares the `RLRunPhase` data kind
  (`RLCollect`, `RLComputeAdvantages`, `RLOptimise`, `RLEvaluate`,
  `RLCheckpoint`) and the singleton GADT `RLRunLifecycle phase` with
  constructors `SRLCollect`, `SRLComputeAdvantages`, `SRLOptimise`,
  `SRLEvaluate`, `SRLCheckpoint`.
- `rlRunPlan :: [RLRunPhase]` and `renderRLRunPhase :: RLRunPhase -> Text`
  preserve the existing five-step run ordering and rendered names.
- The module no longer exports `RunPhase` or `renderRunPhase`; consumers move
  to the GADT-backed surface.
- `test/unit/Main.hs` exercises `renderRLRunPhase` against `rlRunPlan` and
  pins the rendered phase ordering.
- The legacy-ledger row tracking the deviation moves from `Pending Removal`
  to `Completed`.

### Validation

1. `cabal build all` succeeds with the renamed `RLRunPhase` data kind and the
   `RLRunLifecycle` singleton GADT compiling under the existing GHC
   `9.14.1` / Cabal `3.16.1.0` toolchain.
2. `cabal test jitml-unit` passes; the
   `canonical RL environments and framework surfaces are deterministic` case
   continues to assert
   `["collect", "compute-advantages", "optimise", "evaluate", "checkpoint"]`.
3. `grep -RInE 'RunPhase|renderRunPhase' DEVELOPMENT_PLAN documents src test`
   reports no remaining references to the retired flat enum names outside the
   `Completed` ledger entry and this sprint description.

### Remaining Work

None.

## Doctrine Sections Cited

- [../README.md → CLI command topology, typed](../README.md#cli-command-topology-typed) (Sprints 8.2, 8.5 — `jitml train` and `jitml rl *` command leaves)
- [../README.md → Plan / Apply commands](../README.md#doctrine-scope) (Sprints 8.2, 8.5, 8.6 — current dry-run / plan-file surfaces)
- [../README.md → At-Least-Once Event Processing](../README.md#doctrine-scope) (Sprints 8.2, 8.6 — payload-hash deduplication helper)
- [../README.md → Test-suite stanzas](../README.md#test-suite-stanzas) (Sprints 8.1, 8.3, 8.4 — dedicated local `jitml-sl-canonicals` and `jitml-rl-canonicals` bodies)
- [../README.md → GADT-Indexed State Machines](../README.md#doctrine-scope) (Sprint 8.7 — `RLRunLifecycle` joins `TrainingLifecycle` and `TuneSweepLifecycle` as phase-indexed singleton GADTs)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/training_workloads.md` — SL canonical
  summaries, RL algorithm metadata hooks, deterministic trajectory
  helper, `jitml train` / `jitml rl train` summary surfaces, and the
  command-envelope render/parse surfaces plus the `RLRunLifecycle` GADT
  bound to `src/JitML/RL/Framework.hs` after Sprint 8.7; target training
  loops and environment runtime work owned by per-sprint `### Remaining
  Work` blocks.
- `documents/engineering/daemon_architecture.md` — payload-hash
  deduplication helper; target at-least-once `TrainingHandler` and
  `RlHandler` owned by Sprints `8.2` / `8.6` Remaining Work after Sprint
  `5.5` closes the daemon consumer redelivery/dedup substrate.
- `documents/engineering/haskell_code_guide.md` — lifecycle GADT table
  reflects the current `TrainingPhase` / `RLRunPhase` / `TuneSweepPhase`
  data-kind indices co-located in `src/JitML/RL/Framework.hs` after Sprint
  8.7; the daemon-backed runtime layout may later split them.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → Training Workload Surfaces` rows remain aligned
  with `src/JitML/SL/Canonicals.hs`, `src/JitML/RL/Algorithms.hs`, and the
  deterministic phase stanzas.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../README.md](../README.md)

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

✅ **Done** (2026-05-25). Every owned code-surface obligation closed:
the deterministic SL canonical summaries, the typed dataset / loop /
training pipeline (`src/JitML/SL/{Dataset,Loop,Train}.hs`), the RL
framework metadata catalog and primitives
(`src/JitML/RL/{Policy,VecEnv,Buffer,Loop,Framework}.hs`), the
`RLRunLifecycle` GADT, the typed proto envelopes under
`src/JitML/Proto/{Training,Rl,Tune}.hs` with both text and
proto3-compatible byte codecs, the proto-lens cross-language Haskell
bindings under `gen/Proto/Jitml/`, and the pure-Haskell simulator
bindings for cartpole / mountain-car / lunar-lander / atari-subset
under `src/JitML/RL/Simulator.hs`. Live SL training, live broker
daemon handlers, and live statistical convergence + run-to-run reward
determinism (no per-substrate reward fixtures per
[../README.md → Snapshot targets → Numerical-fixture
prohibition](../README.md#snapshot-targets)) are owned by
[phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
Sprints `13.3` / `13.4` / `13.5` / `13.6`. A future real ALE FFI for
atari-subset is filed in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) as
a cross-substrate cleanup; the deterministic stub preserves the
action/obs contract so the upstream RL primitives consume it
identically when the real binding lands.

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
Pulsar command / event topic family; the training and RL modules also parse the
deterministic local text command envelope emitted by their renderers and
round-trip the current command and event envelopes through proto3-compatible
bytes.
Live MinIO dataset fetch, live
Pulsar publish/consume, and real-hardware convergence assertions are
the open work in the per-sprint `### Remaining Work` blocks below.

## Phase Summary

This phase delivers SL plus the RL *framework*. Phase `9` builds on
these primitives to deliver the algorithm catalog (14 traditional RL
algorithms plus AlphaZero), the AlphaZero self-play stack, and the
hyperparameter tuner. Splitting the work this way lets RL framework
changes settle before the algorithm implementations consume them.

## Sprint 8.1: Local Supervised Canonical Summaries ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. Live dataset
fetching through `JitML.Service.MinIOSubprocess`, daemon-backed training
loop on real hardware, live measured convergence fixtures, and the live
SL convergence assertion in `jitml-sl-canonicals` migrated to Phase `13`
Sprint `13.4`. See
[phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md).
**Implementation**: `src/JitML/SL/Canonicals.hs`,
`test/sl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Stand up the current deterministic supervised-learning catalog summary. Real
dataset loaders, daemon-backed training loops, MinIO dataset access, and
live statistical convergence assertions against in-code thresholds remain
target runtime work (no per-substrate `.txt` curve fixtures will be
committed per [../README.md → Snapshot targets → Numerical-fixture
prohibition](../README.md#snapshot-targets)).

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
  MinIO-staged datasets are owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprints `13.2`, `13.3`, and `13.4` once the cluster is up.

### Validation

1. `cabal test jitml-sl-canonicals` exercises the eleven-cell canonical
   summary body and the deterministic `TrainingConfig` convergence pipeline.
2. `jitml train experiments/mnist.dhall` renders the deterministic
   summary from `src/JitML/App.hs`.
3. Live validation (target): a real training run against MNIST clears the
   in-code convergence threshold (`median(test_acc over k seeds) ≥
   literature_target − slack`), the trained checkpoint round-trips, and
   two fresh same-substrate / same-seed runs produce bit-identical
   `sha256(weights.bin)` compared against each other. No `test/golden/sl/`
   fixture is created per [../README.md → Snapshot targets →
   Numerical-fixture prohibition](../README.md#snapshot-targets).

### Remaining Work

- No sprint-owned code-surface Remaining Work remains. The live training
  path (`fetchDatasetRef` plumbing into `TrainingHandler`, daemon-backed
  loop, and the live SL statistical convergence assertion against the
  in-code literature-target threshold) is owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.4`.

## Sprint 8.2: `jitml train` Local CLI Summary ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. The
`proto-lens-protoc` binding generation closed on 2026-05-24 (modules
`Proto.Jitml.Training` and `Proto.Jitml.Training_Fields` under `gen/`,
cabal library re-exports them, `cabal.project` `allow-newer` carries
the `lens-family` / `lens-family-core` pins for GHC 9.14.1, and
`jitml-daemon-lifecycle` validates the cross-language wire-byte
equivalence). Daemon-side `TrainingHandler` against live broker and
the live publish/consume integration test migrated to Phase `13`
Sprints `13.3` / `13.4`.
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
- `encodeTrainingCommandProto` / `decodeTrainingCommandProto` use
  `JitML.Proto.Wire` to round-trip the current `TrainingCommand`
  oneof envelope through strict proto3-compatible bytes.
- `encodeTrainingEventProto` / `decodeTrainingEventProto` round-trip the
  current `TrainingEvent` oneof envelope, including repeated checkpoint
  metrics, through strict proto3-compatible bytes.
- Generated cross-language `proto-lens` output lives under
  `gen/Proto/Jitml/Training.hs` (+ `Training_Fields`); the cabal library
  exposes `Proto.Jitml.Training` and `Proto.Jitml.Training_Fields` so
  callers can decode the same wire bytes through the proto-lens
  `Message` instance for cross-language interop with other-language
  proto3 clients.

### Validation

1. `jitml train --dry-run experiments/mnist.dhall` emits the typed plan
   and exits `0`.
2. `jitml train experiments/mnist.dhall` prints the deterministic
   canonical-problem summary.
3. `cabal test jitml-sl-canonicals` covers render/parse round-trips for
   `StartTraining` and `StopTraining` text command envelopes and
   proto3-compatible binary command/event envelopes.
4. Live validation (target): `jitml train` resolves and SHA-hashes the
   experiment Dhall, reconciles prerequisites, materializes the dataset,
   publishes `StartTraining` on `training.command.<mode>`, the daemon's
   `TrainingHandler` consumes it, and the resulting
   `training.event.<mode>` envelopes drive the report card.

### Remaining Work

- The `proto-lens-protoc` bindings closed on 2026-05-24: generated
  modules `Proto.Jitml.Training` and `Proto.Jitml.Training_Fields`
  live under `gen/`, the cabal library exposes them, and the
  `proto-lens` / `proto-lens-runtime` deps are pinned through
  `cabal.project` `allow-newer` for `lens-family` / `lens-family-core`
  on the GHC 9.14.1 / containers 0.8 baseline. The `gen/` tree is
  excluded from the whitespace lint so regeneration via
  `protoc --plugin=protoc-gen-haskell=$(which proto-lens-protoc)
  --haskell_out=../gen jitml/*.proto` from `proto/` produces a
  drift-free check-code path. Cross-language byte-equivalence is
  validated by the new `local proto3 bytes decode through the
  proto-lens generated InferenceRequest` case in
  `jitml-daemon-lifecycle` (extends the same pattern to Training
  envelopes as the daemon-side handler lands).
- The daemon-side `TrainingHandler` against live broker and the live
  publish/consume integration test are owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprints `13.3` / `13.4`.

## Sprint 8.3: RL Catalog Hook for Canonical Tests ✅

**Status**: Done
**Owned obligations after refactor**: pure-Haskell simulator bindings
for all four canonical RL environments — cartpole and mountain-car
classical-control physics closed on 2026-05-24; lunar-lander
(LunarLander-v2 simplified rigid-body port) and atari-subset
(deterministic 128-byte RAM-state stub matching the Atari
action/obs surface) closed on 2026-05-25 through
`src/JitML/RL/Simulator.hs`. The pure-Haskell route was chosen over a
Box2D / ALE FFI because the README explicitly admits "native Haskell"
envs and re-implementing "the dynamics in Haskell from the published
equations" matches the jitML determinism contract (Box2D float
reductions vary across vendor versions; ALE additionally requires
non-redistributable Atari ROMs and a multi-hour C++ FFI binding
effort). The daemon-backed environment loop migrated to Phase `13`
Sprint `13.5`.
**Implementation**: `src/JitML/RL/Algorithms.hs`,
`src/JitML/RL/Environments.hs`,
`src/JitML/RL/Simulator.hs`,
`test/rl-canonicals/Main.hs`,
`test/unit/Main.hs`
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

- Cartpole and mountain-car classical-control physics closed on
  2026-05-24: `JitML.RL.Simulator` exposes typed `CartPoleState` /
  `MountainCarState` states, deterministic `cartPoleStep` /
  `mountainCarStep` transitions, and `SimulatedEnvironment` values with
  pure step + IO `stepEnvironmentIO` boundaries that match the
  doctrine's `step :: Env -> Action -> IO (Obs, Reward, Done)` signature
  through `RenderFrame`-style observation projection.
- Lunar-lander pure-Haskell port closed on 2026-05-25:
  `JitML.RL.Simulator` exposes `LunarLanderState` (8-dim canonical Gym
  observation), `lunarLanderInitial`, `lunarLanderStep` covering the
  4-discrete-action surface (no-op / left thruster / main engine /
  right thruster) with rigid-body dynamics over gravity + engine
  thrust + angular impulse + ground contact, and the
  `lunarLanderEnvironment` `SimulatedEnvironment` value. Reward
  follows the Gym shaping schedule (distance + velocity + angle
  penalties + leg-contact bonus + engine penalty + terminal
  soft-landing / crash reward). `jitml-unit` covers the no-op gravity
  drift, main-engine counter-thrust, left/right torque, run-to-run
  determinism, and crash-termination cases.
- Atari-subset deterministic-stub closed on 2026-05-25:
  `JitML.RL.Simulator` exposes `AtariSubsetState` (step counter +
  128-byte RAM-state hash), `atariSubsetInitial`, `atariSubsetStep`
  covering the 18-discrete-action surface with a splitmix-style
  RAM-hash advance, and the `atariSubsetEnvironment`
  `SimulatedEnvironment` value. Reward is the normalised low byte of
  the RAM hash; episodes terminate after 250 steps. `jitml-unit`
  covers run-to-run determinism, distinct-action distinctness, and
  the termination boundary. A real ALE binding (full Atari emulator
  + ROM licensing handling + C++ FFI) is filed in the legacy ledger
  as a future cross-substrate cleanup; the deterministic stub
  preserves the action/obs contract so upstream RL primitives consume
  it identically when the real binding lands.
- The daemon-backed environment loop driven by the Phase `5` Pulsar
  consumer is owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.5`.

## Sprint 8.4: RL Metadata Primitives ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. Live HTTP MinIO
wiring of `AsyncSink` migrated to Phase `13` Sprints `13.2` / `13.7`.
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

- No sprint-owned code-surface Remaining Work remains. The live HTTP
  MinIO wiring of `AsyncSink` is owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprints `13.2` and `13.7`.

## Sprint 8.5: RL CLI Summaries and Report Hooks ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. The
`proto-lens` Haskell wire bindings for `rl.proto` closed on
2026-05-24 (`gen/Proto/Jitml/Rl.hs` + `gen/Proto/Jitml/Rl_Fields.hs`
re-exported by the cabal library; `parseRlCommand` remains the
deterministic local text-envelope parser). Daemon-side `RlHandler`
against live broker and the live `StartRLRun → EpisodeDone`
integration test migrated to Phase `13` Sprints `13.3` / `13.6`.
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
- `encodeRlCommandProto` / `decodeRlCommandProto` and
  `encodeRlEventProto` / `decodeRlEventProto` round-trip the current
  `RlCommand` and `RlEvent` oneofs through strict proto3-compatible bytes.
  Generated cross-language bindings remain target work when
  `proto-lens-protoc` lands.

### Validation

1. `jitml rl train --dry-run experiments/cartpole.dhall` emits the typed
   plan.
2. `jitml rl rollout --seed 42` prints a deterministic trajectory.
3. `jitml-unit` verifies the framework catalog and run-plan surface.
4. `cabal test jitml-rl-canonicals` covers render/parse round-trips for
   `StartRLRun` and `StopRLRun` text command envelopes and
   proto3-compatible binary command/event envelopes.
5. Live validation (target): `jitml rl train` publishes `StartRLRun` on
   `rl.command.<mode>`; the daemon's `RlHandler` consumes it, runs the
   real RL loop, and publishes `rl.event.<mode>` envelopes
   (`EpisodeDone`, `EvalDone`, `CheckpointDone`, `MetricUpdate`) that
   round-trip into the report card.

### Remaining Work

- `proto-lens` Haskell wire bindings for `rl.proto` closed on
  2026-05-24: `gen/Proto/Jitml/Rl.hs` and
  `gen/Proto/Jitml/Rl_Fields.hs` are exposed by the cabal library.
  `parseRlCommand` remains the deterministic local text-envelope
  parser; the new `Proto.Jitml.Rl.*` modules are the cross-language
  byte-equivalent binding for other-language proto3 clients.
- The daemon-side `RlHandler` against live broker and the live
  `StartRLRun → EpisodeDone` round-trip are owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprints `13.3` and `13.6`.

## Sprint 8.6: RL Training Plan Surface ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. Daemon `RlHandler`
plumb-through, live reward-threshold + checkpoint/resume equality
assertion migrated to Phase `13` Sprints `13.3` / `13.6`.
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

- No sprint-owned code-surface Remaining Work remains. The daemon-side
  `RlHandler` plumb-through, the live broker + capability classes, and
  the live reward-threshold + checkpoint/resume equality assertion are
  owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprints `13.3` and `13.6`.

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

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
[phase-13-no-caveat-model-runtime.md](phase-13-no-caveat-model-runtime.md),
[../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Own the SL canonical summaries, RL catalog/environment
> metadata, registered rollout helpers, measured command summaries, run-plan
> metadata, and the three GADT-indexed lifecycles. Daemon-backed training
> loops, real datasets, buffers, callbacks, GAE, target networks, and
> live Pulsar events are tracked in the per-sprint `### Remaining Work`
> blocks below.

## Phase Status

✅ **Done** (reopened and re-closed 2026-06-26 for Sprint `8.14` — pure
fixed-budget training witness and inference-ineligibility for partial/untrained
models). `TrainingBudget`, `CompletedTraining`, and the
`InferenceEligibleCheckpoint` boundary are shared by SL, RL, tuning, and
checkpointing; partial, smoke, skipped, seeded-without-witness, and otherwise
untrained manifests cannot flow into inference.

Historical Sprint `8.13` closure:
`trainArchitectureWithDeviceSelected` selects the lowest-validation-loss epoch on a
held-out validation slice (test stays the held-out final eval), the faked SL "loss"
(`1 − accuracy`, `ecValidationLoss = finalLoss`) is replaced with real cross-entropy/MSE
plus a real held-out validation loss in both training-event publishers, a non-wall-clock
SL throughput performance metric (`examples_processed` = train × epochs) is surfaced, and
`documents/engineering/training_metrics_and_splits.md` is authored. **Validated on both
lanes**: `jitml test jitml-sl-canonicals --apple-silicon` 24/24 (real host Metal device)
and `--linux-cpu` 24/24 (real oneDNN), `jitml docs check: ok`, `jitml check-code` green.
All prior Sprints `8.1`–`8.13` remain historical `✅ Done`; Sprint `8.14`
is now closed.

✅ **Done** (re-closed 2026-06-14 — no-caveat framework/runtime surface).
Sprint `8.12` expanded this phase beyond the prior Dense-MLP closure: every
canonical supervised model row now has a substrate-backed trainable runtime
surface, real staged-byte materialization, and live linux-cpu train/eval smoke;
the live MNIST convergence assertion clears the unchanged threshold through the
same `JitML.SL.Architecture` runtime; and the RL framework publishes typed event
payloads rich enough for browser animation/replay instead of string/zero-display
projections. Full cross-model statistical convergence, checkpoint reload, and
inference closure are Phase `13` product-matrix obligations that consume this
surface rather than Phase `8` local-framework obligations.

✅ **Historical closure** (re-closed 2026-06-11 — real-workflow refactor). The SL/RL framework
had shipped real differentiable pure-Haskell networks, but the `jitml train` /
`jitml rl train` paths did not route them through the substrate JIT engine
(`MlpDevice`), and `jitml train` published a closed-form synthetic
`SL.finalLoss` whenever real training was absent. Sprint `8.11` closes the RL
framework routing gap, and Sprint `8.10` closes the fail-closed Dense-MLP
training/eval path plus the residual synthetic SL source. The then-current
[Exit Definition](README.md#exit-definition) item 6 SL obligation was scoped to
the canonical Dense-MLP cohort the JIT MLP ABI trained; Conv2D / ResidualBlock /
VisionTransformer trainable forward/backward JIT support was treated as later
architecture growth. That historical scope is superseded by the 2026-06-14
no-caveat product target: Sprint `8.12` now owns the full canonical SL catalog
trainable-runtime obligation. The live per-lane validation was owned by Phases
`15`/`16`; the linux-cpu and linux-cuda live lanes closed in Phase `15` on
2026-06-11, and the apple-silicon live lane closed in Phase `16` on
2026-06-12. See
[README.md → Reopened phases (2026-06-10)](README.md#reopened-phases-2026-06-10--real-workflow-refactor).
The prior closure narrative below is retained as dated record.

✅ **Done** (re-closed 2026-06-04 after Sprint `8.9`). The original
SL/RL framework code-surface obligations closed on 2026-05-25:
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
[phase-15-linux-cuda-and-cluster-closure.md](phase-15-linux-cuda-and-cluster-closure.md)
Sprints `15.3` / `15.4` / `15.5` / `15.6`. Sprint `8.8` retired the
deterministic atari-subset RAM-state stub behind the runtime-loaded
`JitML.RL.ALE` boundary and explicit ROM handling. The later static
foreign-source correction removed the checked-in C++ shim and Dockerfile/lint
exception; any project-owned ALE adapter must now be generated by Haskell into
the build/cache tree or supplied outside the repository. The stand-in row moved
to Completed in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md#completed).
Sprint `8.9` replaced ROM-dependent default/canonical RL examples with
the copyright-free repo-owned `KeyDoorGrid-v0` environment; the closure lives
in this phase and Phase `9` Sprint `9.8`.

### Current Implementation Scope

The worktree implements the canonical SL catalog and explicitly names the
device-trainable Dense-MLP cohort in `JitML.SL.Canonicals`. `jitml train` is
fail-closed: it requires a live publication plus staged dataset bytes and
trains through `trainClassifierWithDevice` on the selected `MlpDevice`; `jitml
eval` loads checkpoint weights and runs the substrate-bound weighted device
forward. The obsolete synthetic SL curve helpers and deterministic
`SL.Loop` / `SL.Train` pipeline are deleted. The RL framework routes every
MLP-backed trainer through `rlDeviceForSubstrate`; ARS is the lone no-MLP
exception, and the scripted `"simulator"` default is gone. The proto surfaces
(`proto/jitml/{training,rl,tune}.proto` + typed envelopes in
`src/JitML/Proto/{Training,Rl,Tune}.hs`) define the substrate-scoped Pulsar
command / event topic family and round-trip the current command/event envelopes
through proto3-compatible bytes. Live MinIO dataset fetch, live Pulsar
publish/consume, and real-hardware convergence assertions are owned by Phase
`15`. Non-Dense Conv2D / residual / attention SL training remains a named
follow-on that Sprint `8.12` now reclassifies as required no-caveat product
scope.

## Phase Summary

This phase delivers SL plus the RL *framework*. Phase `9` builds on
these primitives to deliver the algorithm catalog (14 traditional RL
algorithms plus AlphaZero), the AlphaZero self-play stack, and the
hyperparameter tuner. Splitting the work this way lets RL framework
changes settle before the algorithm implementations consume them.
Sprint `8.9` re-closed this phase by making the default visual RL demo
copyright-free: `KeyDoorGrid-v0` is now native, tested, and used by the
checked-in replacement RL example instead of `atari-subset`.

## Sprint 8.1: Local Supervised Canonical Summaries ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. Live dataset
fetching through `JitML.Service.MinIOSubprocess`, daemon-backed training
loop on real hardware, live measured convergence fixtures, and the live
SL convergence assertion in `jitml-sl-canonicals` migrated to Phase `15`
Sprint `15.4`. See
[phase-15-linux-cuda-and-cluster-closure.md](phase-15-linux-cuda-and-cluster-closure.md).
**Implementation**: `src/JitML/SL/Canonicals.hs`,
`test/sl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Stand up the supervised-learning catalog, dataset references, and local
canonical test surface. Real dataset loaders, daemon-backed training loops,
MinIO dataset access, and live statistical convergence assertions against
in-code thresholds are closed by the later no-caveat runtime and per-lane
closure phases (no per-substrate `.txt` curve fixtures will be committed per
[../README.md → Snapshot targets → Numerical-fixture
prohibition](../README.md#snapshot-targets)).

### Deliverables

- `src/JitML/SL/Canonicals.hs` declares the eleven current canonical cells:
  `mnist-shallow-mlp`, `mnist-deep-mlp`, `mnist-lenet`,
  `fashion-mnist-mlp`, `fashion-mnist-resnet`, `cifar10-resnet20`,
  `cifar10-resnet56`, `cifar100-wide-resnet`, `cifar10-vit`,
  `tiny-imagenet-resnet50`, and `california-housing-mlp`.
- `denseMlpCohort` names the current device-trainable Dense-MLP subset
  (`mnist-shallow-mlp`, `fashion-mnist-mlp`, `california-housing-mlp`), while
  the non-Dense rows remain target architecture entries until their
  forward/backward JIT codegen lands.
- `test/sl-canonicals/Main.hs` verifies the catalog is populated, the
  Dense-MLP cohort is stable and catalog-backed, and no committed numerical
  curve fixtures are required.
- `src/JitML/SL/Dataset.hs` declares the typed `DatasetRef` / `DatasetSplit`
  surface, the `canonicalDatasets` registry covering MNIST,
  Fashion-MNIST, CIFAR-10, CIFAR-100, Tiny ImageNet, and California
  Housing, the deterministic `expectedSha256` derivation,
  `datasetObjectRef`, `verifyDatasetBytes`, and `fetchDatasetRef` through
  the `HasMinIO` capability boundary.
- Live Pulsar training events backed by real `HasPulsar` and real
  MinIO-staged datasets are owned by
  [phase-15-linux-cuda-and-cluster-closure.md](phase-15-linux-cuda-and-cluster-closure.md)
  Sprints `15.2`, `15.3`, and `15.4` once the cluster is up.

### Validation

1. `cabal test jitml-sl-canonicals` exercises the eleven-cell canonical
   catalog, the Dense-MLP cohort, dataset refs, classifier training, and
   the local convergence-threshold helpers.
2. `jitml train experiments/mnist.dhall` routes through the substrate-backed
   device path once a live publication and staged dataset are present; offline
   execution fails closed with `TrainingPrerequisiteUnmet`.
3. Transferred live validation: a real training run against MNIST clears the
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
  [phase-15-linux-cuda-and-cluster-closure.md](phase-15-linux-cuda-and-cluster-closure.md)
  Sprint `15.4`.

## Sprint 8.2: `jitml train` Local CLI Summary ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. The
`proto-lens-protoc` binding generation closed on 2026-05-24 (modules
`Proto.Jitml.Training` and `Proto.Jitml.Training_Fields` under `gen/`,
cabal library re-exports them, `cabal.project` resolves `lens-family` /
`lens-family-core` from plain Hackage under GHC `9.12.4`, and
`jitml-daemon-lifecycle` validates the cross-language wire-byte
equivalence). Daemon-side `TrainingHandler` against live broker and
the live publish/consume integration test migrated to Phase `15`
Sprints `15.3` / `15.4`.
**Implementation**: `src/JitML/App.hs`, `src/JitML/Plan/Plan.hs`,
`src/JitML/Proto/Training.hs`
**Docs to update**: `documents/engineering/training_workloads.md`,
`documents/engineering/daemon_architecture.md`

### Objective

Wire `jitml train` into the CLI as a Plan/Apply-capable command with a current
local summary body. Pulsar command/event publication is daemon-owned and later
validated by the workflow/runtime closure phases.

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
4. Transferred live validation: `jitml train` resolves and SHA-hashes the
   experiment Dhall, reconciles prerequisites, materializes the dataset,
   publishes `StartTraining` on `training.command.<mode>`, the daemon's
   `TrainingHandler` consumes it, and the resulting
   `training.event.<mode>` envelopes drive the report card.

### Remaining Work

- The `proto-lens-protoc` bindings closed on 2026-05-24: generated
  modules `Proto.Jitml.Training` and `Proto.Jitml.Training_Fields`
  live under `gen/`, the cabal library exposes them, and the
  `proto-lens` / `proto-lens-runtime` deps resolve through plain Hackage
  under the GHC `9.12.4` / `base-4.21` baseline. The `gen/` tree is
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
  [phase-15-linux-cuda-and-cluster-closure.md](phase-15-linux-cuda-and-cluster-closure.md)
  Sprints `15.3` / `15.4`.

## Sprint 8.3: RL Catalog Hook for Canonical Tests ✅

**Status**: Done
**Owned obligations after refactor**: pure-Haskell simulator bindings
for all four canonical RL environments — cartpole and mountain-car
classical-control physics closed on 2026-05-24; lunar-lander
(LunarLander-v2 simplified rigid-body port) and atari-subset
(deterministic 128-byte RAM-state stub matching the Atari
action/obs surface) closed on 2026-05-25 through
`src/JitML/RL/Simulator.hs`. Sprint `8.3` originally chose the pure-Haskell
route over Box2D / ALE FFI because the README admits native Haskell envs and
the determinism contract disfavors cross-version float drift in third-party
physics libraries; the 2026-06-04 Sprint `8.8` reopen supersedes the ALE half
of that choice and keeps ROM handling explicit. The daemon-backed environment
loop migrated to Phase `15` Sprint `15.5`.
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
- `JitML.RL.Algorithms.Common.trajectoryRollout` provides the same-seed
  registered-module rollout surface over real named environment dynamics.
- `test/rl-canonicals/Main.hs` verifies representative catalog entries and
  same-seed rollout determinism without committed trajectory fixtures.
- `src/JitML/RL/Environments.hs` declares the local canonical environment
  catalog for `cartpole`, `mountain-car`, `lunar-lander`, and `atari-subset`,
  plus a deterministic local step helper.
- `src/JitML/RL/VecEnv.hs` declares `VecEnv` and `vecEnvStep`, which
  fan the existing deterministic per-environment step helper across N
  parallel replicas with per-replica seed offsets.
- Full simulator bindings for cartpole, mountain-car, and lunar-lander now live
  in `JitML.RL.Simulator`. The optional `atari-subset` path is limited to the
  runtime-loaded ROM-policy boundary; any adapter needed for real ALE execution
  must be generated by Haskell or supplied outside the repository.

### Validation

1. `cabal test jitml-rl-canonicals` exercises the catalog and the registered
   real-environment rollout surface.
2. `jitml-unit` verifies the canonical environment catalog and
   deterministic step helper.
3. Transferred live validation: real cartpole / mountain-car / lunar-lander
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
  the termination boundary. Reopened Sprint `8.8` owns replacing this
  stand-in with a runtime-loaded ALE boundary, explicit ROM handling, and no
  checked-in C/C++ adapter source; the deterministic stub
  preserves the action/obs contract so upstream RL primitives consume
  it identically when the real binding lands.
- The daemon-backed environment loop driven by the Phase `5` Pulsar
  consumer is owned by
  [phase-15-linux-cuda-and-cluster-closure.md](phase-15-linux-cuda-and-cluster-closure.md)
  Sprint `15.5`.

## Sprint 8.4: RL Metadata Primitives ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. Live HTTP MinIO
wiring of `AsyncSink` migrated to Phase `15` Sprints `15.2` / `15.7`.
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
3. Transferred live validation: real `Policy`, `VecEnv`, replay/rollout
   buffers, and `Async` write discipline are exercised end-to-end against
   running environments through the daemon.

### Remaining Work

- No sprint-owned code-surface Remaining Work remains. The live HTTP
  MinIO wiring of `AsyncSink` is owned by
  [phase-15-linux-cuda-and-cluster-closure.md](phase-15-linux-cuda-and-cluster-closure.md)
  Sprints `15.2` and `15.7`.

## Sprint 8.5: RL CLI Summaries and Report Hooks ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. The
`proto-lens` Haskell wire bindings for `rl.proto` closed on
2026-05-24 (`gen/Proto/Jitml/Rl.hs` + `gen/Proto/Jitml/Rl_Fields.hs`
re-exported by the cabal library; `parseRlCommand` remains the
deterministic local text-envelope parser). Daemon-side `RlHandler`
against live broker and the live `StartRLRun → EpisodeDone`
integration test migrated to Phase `15` Sprints `15.3` / `15.6`.
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
- `jitml rl eval --checkpoint <id>` loads the named checkpoint through the
  substrate inference path.
- `jitml rl rollout --seed <n>` runs a measured on-device PPO rollout and fails
  closed when the substrate device is unavailable.
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
  Generated proto-lens Haskell bindings are checked in under
  `gen/Proto/Jitml/Rl.hs` and `gen/Proto/Jitml/Rl_Fields.hs`.

### Validation

1. `jitml rl train --dry-run experiments/cartpole.dhall` emits the typed
   plan.
2. `jitml rl rollout --seed 42` prints a measured same-seed rollout from the
   registered real-environment generator.
3. `jitml-unit` verifies the framework catalog and run-plan surface.
4. `cabal test jitml-rl-canonicals` covers render/parse round-trips for
   `StartRLRun` and `StopRLRun` text command envelopes and
   proto3-compatible binary command/event envelopes.
5. Transferred live validation: `jitml rl train` publishes `StartRLRun` on
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
  [phase-15-linux-cuda-and-cluster-closure.md](phase-15-linux-cuda-and-cluster-closure.md)
  Sprints `15.3` and `15.6`.

## Sprint 8.6: RL Training Plan Surface ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. Daemon `RlHandler`
plumb-through, live reward-threshold + checkpoint/resume equality
assertion migrated to Phase `15` Sprints `15.3` / `15.6`.
**Implementation**: `src/JitML/App.hs`, `src/JitML/Plan/Plan.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Expose the current RL training plan surface. Real typed RL training pipelines
are closed by the later no-caveat runtime and per-lane closure phases.

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
- Historical Sprint `8.4` note: daemon-backed training execution against live
  Pulsar / live MinIO was later implemented for the scoped workflow surface;
  Sprint `9.12` / Phase `13` now expand the same standard to the full
  no-caveat RL matrix.

### Validation

1. `jitml rl train --dry-run experiments/cartpole.dhall` emits the typed
   plan.
2. `jitml rl train experiments/cartpole.dhall` prints the algorithm
   catalog summary.
3. `cabal test jitml-rl-canonicals` verifies the deterministic local
   `RLLoop` records rollout transitions into its `ReplayBuffer`.
4. Transferred live validation: a real `RLLoop` executes against the daemon
   for one cartpole episode, reaches the reward threshold, and the
   resulting checkpoint resumes bit-deterministically to the same reward.

### Remaining Work

- No sprint-owned code-surface Remaining Work remains. The daemon-side
  `RlHandler` plumb-through, the live broker + capability classes, and
  the live reward-threshold + checkpoint/resume equality assertion are
  owned by
  [phase-15-linux-cuda-and-cluster-closure.md](phase-15-linux-cuda-and-cluster-closure.md)
  Sprints `15.3` and `15.6`.

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
   `9.12.4` / Cabal `3.16.1.0` toolchain.
2. `cabal test jitml-unit` passes; the
   `canonical RL environments and framework surfaces are deterministic` case
   continues to assert
   `["collect", "compute-advantages", "optimise", "evaluate", "checkpoint"]`.
3. `grep -RInE 'RunPhase|renderRunPhase' DEVELOPMENT_PLAN documents src test`
   reports no remaining references to the retired flat enum names outside the
   `Completed` ledger entry and this sprint description.

### Remaining Work

None.

## Sprint 8.8: ALE Boundary and ROM Policy ✅

**Status**: Done
**Implementation**: `docker/Dockerfile`, `src/JitML/RL/ALE.hs`,
`src/JitML/RL/Simulator.hs`,
`src/JitML/RL/Environments.hs`, `test/rl-canonicals/Main.hs`,
`test/integration/Main.hs`
**Docs to update**: `README.md`,
`documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/code_quality.md`,
`documents/engineering/training_workloads.md`,
`documents/engineering/unit_testing_policy.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Remove the deterministic `atari-subset` RAM-state production stub and preserve
the current action/observation contract consumed by `AlgorithmModule`, `VecEnv`,
`RLLoop`, and the daemon-backed RL path through an explicit ROM-policy boundary.

### Deliverables

- `jitml:local` may build the ALE library/runtime from a pinned upstream tag or
  source SHA during image construction; do not depend on an Ubuntu `libale-dev`
  package, because the 2026-06-04 Ubuntu 24.04 image validation found no such
  package candidate.
- The Haskell FFI boundary lives behind `JitML.RL.ALE` rather than binding
  directly to C++ symbols from simulator code. The repository carries no
  checked-in C/C++ adapter source. If optional ALE execution is retained, the
  adapter operations Haskell needs (create/destroy, load ROM, reset, act,
  game-over, get RAM, get screen, legal actions, and seed) must come from a
  Haskell-generated build/cache artifact or an operator-supplied external
  library path.
- ROM inputs are explicit and uncommitted: `RunConfig.atariRomPath`,
  `JITML_ATARI_ROM`, or compatibility `JITML_ALE_ROM` names a local file,
  with developer ROMs kept under ignored `./.roms/`. No commercial ROM bytes
  enter the repository or image.
- `atari-subset` in the production training path no longer uses the
  deterministic RAM-state implementation as a production fallback. If an ALE
  runtime shim is unavailable, the path fails closed rather than using a static
  checked-in native source file.
- The `Deterministic atari-subset RAM-state stub` row moves from Pending
  Removal to Completed in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

### Validation

1. `docker compose build jitml` builds the image and runs the container-only
   `jitml check-code` gate without compiling any checked-in C/C++ adapter
   source.
2. `cabal test jitml-unit jitml-rl-canonicals` validates the explicit
   no-ROM policy without committing ROM bytes. A separate manual ALE smoke run
   may validate same-seed determinism, legal action reporting, RAM dimension,
   screen dimension, reset, and a short episode when an operator supplies a ROM
   they are allowed to use.
3. `jitml rl train` with `envName = "atari-subset"` fails closed with the
   ROM-policy diagnostic when no explicit ROM is present, and no required
   validation depends on a ROM or checked-in adapter source.

2026-06-04 validation evidence:

- `docker compose build jitml` passed. The Docker image built ALE
  `v0.12.0` / commit `94c24368664b8539c53857522e50652ddcc44b20`, built
  the then-current `exe:jitml` / `exe:jitml-demo` pair, ran image-local
  `jitml check-code` with `check-code: ok`, built the PureScript bundle, and
  exported `jitml:local`. Sprint `11.10` later folded `jitml-demo` into the
  one-binary Webapp role.
- `docker compose run --rm jitml jitml check-code` passed with
  `check-code: ok`.
- `docker compose run --rm jitml cabal test jitml-unit jitml-rl-canonicals
  --jobs=2` passed: `jitml-unit` 183 / 183 and `jitml-rl-canonicals` 26 / 26.
  ROM-backed ALE smoke is optional/manual and was not part of required
  validation.
- The production no-ROM assertion passed by running `jitml rl train` with
  `JITML_ENVIRONMENT=atari-subset`, `JITML_MAX_STEPS=4`,
  `JITML_EVAL_EPISODES=1`, and no ROM env vars; the command failed closed and
  printed the ROM-policy diagnostic naming `JITML_ATARI_ROM`, `JITML_ALE_ROM`,
  and `RunConfig.atariRomPath`.
- The 2026-06-04 static-foreign-source correction deleted
  `csrc/jitml_ale_shim.cpp`, removed the Dockerfile compile step for
  `/usr/local/lib/libjitml_ale_shim.so`, and removed the lint allowlist. The
  remaining Haskell `JitML.RL.ALE` path requires a generated or externally
  supplied runtime shim for optional manual ALE execution.

### Remaining Work

None.

## Sprint 8.9: Copyright-Free Visual RL Demo Environment ✅

**Status**: Done
**Implementation**: `src/JitML/RL/Environments.hs`,
`src/JitML/RL/Simulator.hs`, `src/JitML/RL/SimulatorLoop.hs`,
`src/JitML/RL/ConvergenceThresholds.hs`, `src/JitML/App.hs`,
`test/unit/Main.hs`, `test/rl-canonicals/Main.hs`,
`experiments/key-door-grid.dhall`
**Docs to update**: `README.md`,
`documents/engineering/training_workloads.md`,
`documents/engineering/unit_testing_policy.md`,
`documents/engineering/code_quality.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Replace ROM-dependent default RL examples with a repo-owned visual
discrete-control environment, `KeyDoorGrid-v0`, so jitML demos and required
canonical tests never require copyrighted Atari ROM bytes.

### Deliverables

- `KeyDoorGrid-v0` is added to the canonical environment catalog as a native
  Haskell environment with deterministic seeded map generation.
- The environment exposes a discrete action surface with a legal-action mask:
  move north/south/east/west, pick up key, and open door.
- Observations include stable grid channels plus agent inventory state; render
  frames are generated from Haskell data, not external assets.
- The default RL examples and `jitml rl train` demo path target
  copyright-free environments (`cartpole`, `lunar-lander`, or
  `KeyDoorGrid-v0`) rather than `atari-subset`.
- `atari-subset` remains optional runtime support only if retained; it is not
  part of default examples, canonical demo validation, or required phase
  closure. Any retained ALE adapter must be generated by Haskell or supplied
  outside the repository.

### Validation

1. `docker compose run --rm jitml cabal test jitml-unit
   jitml-rl-canonicals --jobs=2` passes with KeyDoorGrid coverage for same-seed
   layout determinism, legal-action masks, key pickup, door opening, goal
   termination, render-frame determinism, and run-to-run trajectory equality.
2. `docker compose run --rm jitml jitml rl train experiments/cartpole.dhall`
   or the replacement checked-in RL example runs without requiring any ROM path.
3. `rg -n 'AtariSubset-v0|atari-subset' README.md documents experiments
   DEVELOPMENT_PLAN` shows only optional ALE/runtime-support references and
   historical ledger entries, not default demo or required canonical coverage.
4. `docker compose run --rm jitml jitml check-code` passes.

### Validation Re-run (2026-06-04)

- `docker compose run --rm jitml jitml check-code` passed during
  `jitml:local` image construction with `check-code: ok`.
- `docker compose run --rm -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' jitml cabal test jitml-unit jitml-rl-canonicals --jobs=2`
  ran after the GHC `9.12.4` downgrade; `jitml-rl-canonicals` passed 27 / 27,
  and `jitml-unit` exposed only the cache-key golden drift caused by the new
  toolchain fingerprint.
- `docker compose run --rm -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' jitml cabal test jitml-unit --jobs=2`
  passed 184 / 184 after refreshing the deterministic cache-key snapshot. The
  process-local Git `safe.directory=*` setting is scoped to the mounted
  worktree inside the container; it does not change repository state.
- `docker compose run --rm -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' -e JITML_ENVIRONMENT=key-door-grid jitml jitml rl train experiments/key-door-grid.dhall`
  exited `0` and rendered `environment: key-door-grid` with no ROM path.

### Remaining Work

None.

## Sprint 8.10: SL Substrate-Backed Training + Real Eval ✅

**Status**: Done
**Implementation**: `src/JitML/SL/Classifier.hs`, `src/JitML/Numerics/MlpDevice.hs`, `src/JitML/App.hs` (`runTrain`, `runEval`), `src/JitML/SL/Canonicals.hs`, `src/JitML/SL/ConvergenceThresholds.hs`, `src/JitML/AppError/AppError.hs`
**Docs to update**: `../documents/engineering/training_workloads.md`, `../documents/engineering/checkpoint_format.md`, `system-components.md`

### Objective

Make `jitml train` and `jitml eval` exercise a real, substrate-backed model on the
resolved `--substrate`, with **no synthetic or pure-Haskell fallback on any runtime
path**. Owns the [Exit Definition](README.md#exit-definition) item 6 SL slice for
the canonical Dense-MLP cohort and item 7 inference-read slice (`runEval`).

### Deliverables

- `mlpDeviceForSubstrate :: Substrate -> Env -> MlpDevice` selecting
  `oneDnnMlpDevice` / `cudaMlpDevice` / `metalMlpDevice` for `LinuxCPU` /
  `LinuxCUDA` / `AppleSilicon` (in `JitML.Numerics.MlpDevice`, or a small
  `MlpDeviceSelect` module if an import cycle arises).
- A device-backed classifier trainer in `JitML.SL.Classifier` mirroring
  `trainPolicyValueNetOnSamplesWithDevice` — batched `mlpdForwardBatch` /
  `mlpdBatchGradient`, host-side softmax-cross-entropy head + Adam — returning
  `IO (Either Text (TrainedClassifier, Double))`; a `Left` propagates as a hard
  error (no pure fallback).
- `runTrain` resolves the substrate (reusing the `workerBrokerTarget` resolution),
  **requires** a live publication and a staged dataset, and otherwise
  `exitWithError (TrainingPrerequisiteUnmet …)` — nothing printed or published on
  failure; only the measured loss is published via `publishWorkerTrainingEvent`.
- `runEval` loads the `.jmw1` weight blob and computes a real held-out
  accuracy/loss through the device forward; missing checkpoint/test bytes →
  `InferenceCheckpointMissing`.
- `canonicalProblems` + `ConvergenceThresholds` scoped to the Dense-MLP cohort the
  JIT codegen trains; new `AppError` variants added to the single ADT and
  registered in `system-components.md`. Non-Dense canonical rows remain catalog
  entries for future trainable-architecture expansion, not the current closure
  gate.

### Validation

- `docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu`
  (device-backed convergence; live half in Sprint 15.17).
- Offline `jitml train` → typed error, exit 2, no number printed/published.
- `jitml check-code` + `jitml docs check` green inside `jitml:local`.

### Current Validation State

Host (`ghc-9.12.4`, no oneDNN/Metal toolchain) — landed and green:

- `JitML.SL.Classifier.trainClassifierWithDevice` /
  `trainClassifierWithDeviceFromIdxBounded` / `classifyWithDevice` /
  `accuracyWithDevice` route the softmax cross-entropy classifier through the
  injected `MlpDevice` (batched device forward + batched device gradient +
  host Adam), failing closed on a device `Left` — no pure-Haskell fallback.
- `runTrain` is fail-closed: `runDeviceMnistTraining` requires a live cluster
  publication and a staged dataset, otherwise `exitWithError
  (TrainingPrerequisiteUnmet …)` with nothing printed or published. The
  synthetic `train:`/`final_loss:` summary print is removed.
- `runEval` loads the named inference checkpoint and runs the substrate-bound
  weighted device forward; a missing pointer/manifest → `InferenceCheckpointMissing`.
- `AppError` gains `TrainingPrerequisiteUnmet Text` (exit 2) with its
  `renderError` line; registered in `system-components.md`.
- `JitML.SL.Canonicals.denseMlpCohort` / `isDenseMlpProblem` name the
  device-trainable single-hidden-layer Dense subset
  (`mnist-shallow-mlp`, `fashion-mnist-mlp`, `california-housing-mlp`).
- The residual synthetic `convergenceCurve` / `finalLoss` symbols and the
  `SL.Loop` / `SL.Train` deterministic-curve pipeline were deleted on
  2026-06-11; the ledger rows moved to `Completed`.
- `jitml-unit` (196/196, before the 2026-06-11 residual-source deletion),
  `jitml-sl-canonicals` (host device case skips when the probe reports no
  device), and `jitml-integration` Subprocess offline-`jitml train`
  fail-closed assertion pass on the host.

Container (`jitml:local`, oneDNN present) — boundary gate **passed**:

- `docker compose build jitml` built `jitml:local` with `check-code: ok`.
- `docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu`
  → **15/15 PASS** on 2026-06-11, including `SL classifier converges through
  the substrate JIT device (Sprint 8.10 --linux-cpu): OK (0.75s)` — the case ran the real
  generated oneDNN MLP kernel (compile + batched forward/gradient + Adam to
  convergence) instead of skipping.
- `docker compose run --rm jitml-cuda jitml test jitml-sl-canonicals
  --linux-cuda` → **15/15 PASS** on 2026-06-11 against the RTX 5090 CUDA lane.
- Live linux-cpu and linux-cuda workflow exercise closed in Phase `15` on
  2026-06-11: both lanes bootstrapped clean data and passed full live
  `jitml-integration` **67/67** plus `jitml-e2e` **20/20**.
- Continuation audit (2026-06-11): `docker compose run --rm jitml jitml test
  jitml-sl-canonicals --linux-cpu` revalidated the then-current Dense-MLP surface
  (**15/15 PASS**, including the device-backed classifier convergence case).
  Latest rerun: the device case reported
  `SL classifier converges through the substrate JIT device (Sprint 8.10
  --linux-cpu): OK (1.22s)`.
  This closes Sprint `8.10` against the current Exit Definition item 6 Dense-MLP
  scope. The repository still has no trainable non-Dense SL ABI: the available
  classifier path is the two-layer `MlpDevice` forward/batch-gradient ABI, while
  Conv2D / residual / ViT catalog rows need architecture-specific parameter
  layouts plus backward JIT kernels before they can become trainable follow-on
  cohorts.
- Code-boundary audit (2026-06-11): `JitML.Numerics.MlpDevice` exposes only the
  `jitml_mlp_*` two-layer MLP ABI, `JitML.SL.Classifier` trains only
  `MlpParams`, and `JitML.SL.Canonicals.denseMlpCohort` still filters by
  `problemModel == "Dense"`. The existing weighted Conv2D / BatchNorm /
  LayerNorm / MHA / Embedding codegen in `JitML.Codegen.{OneDnn,Cuda,Metal}`
  is forward/kernel-family coverage, not the supervised trainable-architecture
  backward ABI required to promote the non-Dense canonical rows.

### Remaining Work

None.

### Follow-on Scope

Historical note: this follow-on scope was superseded on 2026-06-14. Conv2D /
ResidualBlock / VisionTransformer forward+backward JIT codegen and backward
kernels are now part of Sprint `8.12` / Phase `13` no-caveat product closure,
not non-blocking future growth.

## Sprint 8.11: RL Framework Substrate Routing ✅

**Status**: Done
**Implementation**: `src/JitML/App.hs` (`runTrainerEpisodes`, `runRl`), `src/JitML/Numerics/MlpDevice.hs`, `src/JitML/RL/SimulatorLoop.hs`
**Docs to update**: `../documents/engineering/training_workloads.md`, `system-components.md`

### Objective

Route every MLP-backed RL trainer through the substrate engine selected by
`--substrate`, and remove the scripted non-learning default. Owns the
[Exit Definition](README.md#exit-definition) item 6 RL slice.

### Deliverables

- `rlDeviceForSubstrate :: Substrate -> Env -> MlpDevice` — one DRY seam for the 13
  MLP-backed algorithms; **ARS is the lone no-MLP exception**, stated once here and
  in `system-components.md`.
- `runTrainerEpisodes` dispatches each named trainer to its `*OnDevice` variant via
  the seam; iteration budgets raised so training actually learns (replacing
  `ppoNumIterations = max 1 evalEpisodes`).
- The `"simulator"` scripted default is removed; an unknown trainer →
  `InvalidConfig`, never a scripted fallback.

### Validation

- `docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`
  (on-device reward improvement; live half in Sprint 15.17).
- Unknown `JITML_RL_TRAINER` → typed `InvalidConfig`, no episodes published.

### Current Validation State

Host (`ghc-9.12.4`, no oneDNN/Metal toolchain) — landed and green:

- `JitML.Numerics.MlpDeviceSelect.rlDeviceForSubstrate` is the single DRY seam
  for the 13 MLP-backed algorithms; ARS is the lone no-MLP exception, stated
  here and in `system-components.md`.
- `runTrainerEpisodes` takes the resolved `MlpDevice`, probes it once
  (`probeMlpDevice` — a 1×1×1 JIT forward) and **fails closed** when the
  substrate toolchain/hardware is absent, then dispatches each trainer to its
  `*OnDevice` variant. Iteration budgets are raised from the old
  `max 1 evalEpisodes` floor (PPO `max 50 evalEpisodes`, value-based / continuous
  `max 20000 (evalEpisodes × maxSteps)`, ARS `max 50 evalEpisodes`, HER
  `max 200 (evalEpisodes × 20)`) so training actually learns.
- The `"simulator"` scripted default is gone: `runRl` defaults the trainer to
  `ppo`, and an unknown trainer → `runTrainerEpisodes` returns `Left` →
  `runRl` `exitWithError (InvalidConfig …)`; nothing is published.
- `jitml-rl-canonicals` (27/27) passes on the host, including the new
  on-device PPO reward-improvement case, which skips when the device probe
  reports no toolchain.

Container (`jitml:local`, oneDNN present) — boundary gate **passed**:
`docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`
→ **27/27 PASS** on 2026-06-11, including `PPO trains and improves on cartpole
through the substrate JIT device (Sprint 8.11 --linux-cpu): OK (0.75s)` — the case ran the
real generated oneDNN MLP kernel through `trainOnPolicyOnDevice` instead of
skipping. `check-code: ok` in the same image. The CUDA lane also passed
`docker compose run --rm jitml-cuda jitml test jitml-rl-canonicals
--linux-cuda` **27/27** on 2026-06-11. Live PPO convergence is stable on both
Linux substrates with substrate-specific tuning: `linux-cpu` uses 10 PPO epochs
per update at `5.0e-4`, while `linux-cuda` uses 8 epochs at `7.0e-4`; focused
and full live integration passed on both lanes.

### Remaining Work

- None on the owned RL-routing surface. The per-trainer internal device updates
  (`dqnUpdateDevice` and the `QrDqnTrainer` / `ContinuousTrainer` / `HerTrainer`
  peers) now **fail closed** on a mid-run device `Left` (no pure-Haskell
  fallback); the ledger row moved to `Completed`. The live `--linux-cpu` /
  `--apple-silicon` on-device reward exercise is owned by Phases `15`/`16`.

## Sprint 8.12: No-Caveat SL/RL Framework Runtime ✅

**Status**: Done
**Implementation**: `src/JitML/SL/Canonicals.hs`, `src/JitML/SL/Classifier.hs`,
`src/JitML/RL/Framework.hs`, `src/JitML/RL/SimulatorLoop.hs`,
`src/JitML/Proto/{Training,Rl,Tune}.hs`
**Docs to update**: `documents/engineering/training_workloads.md`,
`documents/engineering/numerical_core.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Promote the full advertised SL/RL framework surface into runtime obligations
instead of scoped Dense-MLP and text-event closure.

### Deliverables

- Every canonical SL row is either trainable through a substrate-backed
  architecture-specific forward/backward ABI or removed from the canonical
  product claim. The intended no-caveat target keeps the rows and implements the
  missing Dense-deep, Conv2D, residual, wide-residual, ResNet-50, and
  VisionTransformer training paths.
- `JitML.SL.Canonicals.denseMlpCohort` stops being the product gate; all
  canonical SL rows run against real staged dataset bytes through the
  substrate-backed architecture runtime with no synthetic dataset or curve
  fallback. Phase `13` promotes that staged-byte train/eval surface to the full
  median-convergence, checkpoint, reload, and inference matrix.
- RL command/event payloads include typed episode frames, observations/actions,
  policy probabilities, replay-buffer state, and checkpoint references required
  by browser animation and replay.
- The framework emits typed live events that `jitml-demo` can decode through
  generated browser contracts rather than free-form text frames.
- Any temporary framework helper used to keep existing tests green while this
  lands is listed in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md#pending-removal).

### Progress (2026-06-14)

- `src/JitML/Proto/Rl.hs` and `proto/jitml/rl.proto` now define
  `RlAnimationFrame` and `RlReplayFrame` event payloads with typed observation,
  action, reward, policy-probability, replay-cursor, and timestamp fields.
  `encodeRlEventProto` / `decodeRlEventProto` cover both new oneof cases, and
  `parseRlEvent` round-trips the rendered line envelope used by the current
  broker bridge.
- `src/JitML/RL/SimulatorLoop.hs` records deterministic per-step
  `SimulatedFrame` transitions from real environment dynamics; the worker and
  host RL publishers convert those frames into `RlAnimationFrame` events on
  `rl.event.<mode>` when an episode carries frame data.
- `src/JitML/Web/Contracts.hs` renders generated PureScript
  `RlAnimationFrame` / `RlReplayFrame` records into
  `web/src/Generated/Contracts.purs`; `web/src/Panels/Rl.purs` consumes the
  generated animation record, preserves unsigned hash/cursor/timestamp fields
  as exact strings rather than lossy browser `Int` values, and rejects the old
  catch-all `data:` placeholder. The interactive browser replay control remains
  Phase `14` work.
- `src/JitML/SL/Architecture.hs` now owns the all-row supervised architecture
  runtime. It maps every `JitML.SL.Canonicals.canonicalProblems` row to a
  substrate-backed trainable topology: the Dense and DeepDense rows are device
  MLP stacks, residual rows are device MLP residual stacks with real
  input-gradient propagation, `Conv2D` uses a shared patch-convolution stem plus
  pooled classifier, and `VisionTransformer` uses patch embeddings plus a
  trainable Q/K/V self-attention block before pooling and classification. Each
  trainable layer calls the injected `MlpDevice` batched forward,
  batch-gradient, and input-gradient ABI; device failure returns `Left` with no
  pure-Haskell fallback.
- `JitML.SL.Canonicals.trainableCanonicalCohort` is the new all-row product
  cohort. `denseMlpCohort` remains only as a named legacy compatibility helper
  while the remaining Dense-only callers are deleted under the legacy ledger.
- `jitml train` now decodes the supervised experiment Dhall through
  `JitML.SL.Canonicals.loadCanonicalProblemExperiment`, resolves the row's
  `ArchitectureSpec`, decodes staged IDX bytes once through
  `JitML.SL.Classifier.decodeBoundedDataset`, and trains through
  `Architecture.trainArchitectureWithDevice` instead of the Dense-only
  classifier entry. Rows whose real dataset artifacts are not SHA-pinned or not
  staged still fail closed before publishing.
- `JitML.SL.Dataset` now has an explicit `ArchiveArtifact` for tarball-backed
  datasets plus real upstream SHA-256 pins for the canonical Toronto
  `cifar-10-binary.tar.gz` and `cifar-100-binary.tar.gz` archives.
  `jitml internal upload-dataset --artifact archive` accepts those tarballs,
  verifies the pinned SHA, and stages them at
  `jitml-datasets/<name>/<split>/archive.tar.gz`. `JitML.SL.Archive` extracts
  regular-file payloads from the gzip tar archives, and
  `JitML.SL.Classifier` now materializes the official CIFAR-10 train/test batch
  files and CIFAR-100 train/test files into labeled 3072-feature examples, using
  CIFAR-100 fine labels as the supervised target.
- `JitML.SL.Dataset` also pins the scikit-learn/Figshare
  `cal_housing.tgz` archive, and the new `JitML.SL.Regression` module parses
  `CaliforniaHousing/cal_housing.data` directly from the archive into
  eight-feature regression examples with the raw median-house-value target and
  trains a one-output MSE regressor through the selected `MlpDevice`.
  `jitml train` now routes staged California Housing archives through that
  regression trainer. Regression checkpoint/inference/convergence gates remain
  open; the runtime no longer depends on synthetic tabular examples.
- `JitML.SL.Dataset` now pins the canonical `tiny-imagenet-200.zip` archive,
  and the new `JitML.SL.TinyImageNet` module parses the real metadata files
  (`wnids.txt`, `words.txt`, and `val_annotations.txt`), decodes JPEG pixels
  through `JuicyPixels`, and materializes train/validation labeled examples
  from the real Zip64 archive through a narrow central-directory reader that
  supports Zip64 size/offset records plus stored/deflated ZIP entries.
- `jitml train` now has archive-backed live routes for CIFAR-10, CIFAR-100, and
  California Housing, and Tiny ImageNet: it fetches the staged
  `ArchiveArtifact`, materializes the train/test rows for CIFAR through
  `JitML.SL.Archive` + `JitML.SL.Classifier`, materializes Tiny ImageNet from
  zip/JPEG bytes through `JitML.SL.TinyImageNet`, trains image classifiers
  through `JitML.SL.Architecture`, and trains California Housing through the new
  `JitML.SL.Regression` MSE path. Missing archives still fail closed before
  publishing.
- Validation on 2026-06-14 built `jitml:local` with
  `docker compose --progress plain build jitml`: the image-local gate reported
  `check-code: ok`, rebuilt the PureScript bundle with zero PureScript warnings,
  and exported the image. The focused PureScript smoke check also passed 9 / 9 in
  a disposable container before the full image rebuild.
- `docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`
  passed 28 / 28 on 2026-06-14, including the new typed
  `RlAnimationFrame` / `RlReplayFrame` proto/render/parse coverage and simulator
  transition-frame assertions.
- `docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu`
  passed 23 / 23 on 2026-06-14. The added Sprint `8.12` cases assert the
  trainable canonical cohort covers all eleven product rows, resolve supervised
  experiment Dhall to the canonical row, pin Fashion-MNIST train/test
  image+label artifacts to upstream gzip SHA-256 values, pin the CIFAR-10 and
  CIFAR-100 upstream binary archives to SHA-256 values computed from the
  canonical Toronto downloads, parse CIFAR binary records, pin and parse the
  California Housing archive/data row format, pin the Tiny ImageNet archive and
  materialize generated JPEGs from a real zip layout, execute one
  substrate-backed train step for every canonical architecture through oneDNN,
  and train a real regression model through the same oneDNN `MlpDevice`.
  The live MNIST convergence assertion now decodes staged train/test IDX bytes
  and, when a live publication exists, trains and evaluates through
  `JitML.SL.Architecture.trainArchitectureWithDevice` /
  `accuracyArchitectureWithDevice` on the selected `MlpDevice` rather than the
  legacy Dense-only classifier path.
- `docker compose run --rm jitml jitml check-code` passed (`check-code: ok`) on
  2026-06-14 after adding the all-row SL architecture runtime, and re-passed
  after moving the live MNIST convergence assertion onto the architecture/device
  path.
- `docker compose run --rm jitml jitml docs check` passed (`docs check: ok`) on
  2026-06-14 after aligning the development plan and engineering workload docs.
- After the CIFAR archive/parser slice, `docker compose run --rm jitml cabal run
  jitml -- check-code` passed (`check-code: ok`) and
  `docker compose run --rm jitml cabal run jitml -- docs check` passed
  (`docs check: ok`) on 2026-06-14. These were run through Cabal so the
  generated-doc comparison used the current source tree rather than the
  pre-slice image binary.
- After the California Housing archive/parser slice, `docker compose run --rm
  jitml cabal run jitml -- check-code` passed (`check-code: ok`) and
  `docker compose run --rm jitml cabal run jitml -- docs check` passed
  (`docs check: ok`) on 2026-06-14.
- After the Tiny ImageNet archive/metadata parser slice, `docker compose run
  --rm jitml cabal run jitml -- check-code` passed (`check-code: ok`) and
  `docker compose run --rm jitml cabal run jitml -- docs check` passed
  (`docs check: ok`) on 2026-06-14.
- After the tar archive materialization slice, `docker compose run --rm jitml
  jitml test jitml-sl-canonicals --linux-cpu` still passed 22 / 22, with the
  CIFAR and California archive decoders exercised by the existing Sprint `8.12`
  parser cases.
- The tar archive materialization slice also passed `docker compose run --rm
  jitml cabal run jitml -- check-code` (`check-code: ok`) and
  `docker compose run --rm jitml cabal run jitml -- docs check`
  (`docs check: ok`) on 2026-06-14.
- After the regression-runtime slice, `docker compose run --rm jitml jitml test
  jitml-sl-canonicals --linux-cpu` passed 23 / 23, including the new
  device-backed regression convergence case.
- The regression-runtime and archive-backed `jitml train` routing slice also
  passed `docker compose run --rm jitml cabal run jitml -- check-code`
  (`check-code: ok`) and `docker compose run --rm jitml cabal run jitml -- docs
  check` (`docs check: ok`) on 2026-06-14.
- After the Tiny ImageNet zip/JPEG materialization slice, `docker compose run
  --rm jitml jitml test jitml-sl-canonicals --linux-cpu` passed 23 / 23,
  including in-memory zip archive materialization and JPEG decoding through
  `JuicyPixels`.
- The Tiny ImageNet zip/JPEG materialization slice also passed
  `docker compose run --rm jitml cabal run jitml -- check-code`
  (`check-code: ok`) and `docker compose run --rm jitml cabal run jitml -- docs
  check` (`docs check: ok`) on 2026-06-14.
- Live linux-cpu prerequisite setup on 2026-06-14 bootstrapped the cluster with
  `docker compose run --rm jitml jitml bootstrap --linux-cpu`; the published
  `.build/runtime/cluster-publication.json` reported Harbor, MinIO, Pulsar,
  PostgreSQL, observability, `jitml-service`, and `jitml-demo` ready behind edge
  port `9091`. MNIST, Fashion-MNIST, CIFAR-10, CIFAR-100, California Housing,
  and Tiny ImageNet source artifacts were staged into live MinIO through
  `jitml internal upload-dataset`, with each upload SHA-verified against the
  canonical pins in `JitML.SL.Dataset`.
- After replacing the Tiny ImageNet decoder's `zip-archive` path with the
  project-owned Zip64-aware reader, `docker compose run --rm jitml cabal test
  jitml-sl-canonicals --test-options='--pattern=8.12'` passed 9 / 9 on
  2026-06-14. That focused gate includes the live all-row SL matrix: every
  canonical row fetched its staged MinIO bytes, materialized real train/test
  examples, trained through the selected linux-cpu `MlpDevice`, and evaluated
  finite metrics through the same architecture runtime.
- After increasing the live MNIST validation budget to 60 full-batch device
  epochs at `1.0e-2` while leaving the threshold unchanged,
  `docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu`
  passed 24 / 24 on 2026-06-14. The live MNIST convergence case cleared the
  in-code threshold through `JitML.SL.Architecture` in 393.09s, and the live
  all-row staged-byte matrix passed in 38.90s.
- `docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`
  re-passed 28 / 28 on 2026-06-14 after the SL live-gate fix.

### Validation

- `docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu`
- `docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`
- `docker compose run --rm jitml jitml check-code`
- `docker compose run --rm jitml jitml docs check`

Current validated subset (2026-06-14):

- `docker compose --progress plain build jitml` passed (`check-code: ok` and
  PureScript bundle build succeeded).
- `docker compose run --rm jitml jitml check-code` passed (`check-code: ok`)
  after the all-row SL architecture runtime landed and after the live MNIST
  convergence assertion was moved to the architecture/device runtime. The
  current-source reruns after the CIFAR, California, Tiny ImageNet metadata, tar
  materialization, regression-runtime, and Tiny ImageNet zip/JPEG slices passed
  as
  `docker compose run --rm jitml cabal run jitml -- check-code`.
- `docker compose run --rm jitml jitml docs check` passed (`docs check: ok`)
  after the Phase `8` plan and engineering docs were aligned. The current-source
  reruns after generated CLI docs and Phase `8` docs changed passed as
  `docker compose run --rm jitml cabal run jitml -- docs check`.
- `docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu`
  passed 23 / 23, including all-row trainable-cohort coverage, supervised
  experiment Dhall row resolution, Fashion-MNIST real-artifact SHA coverage,
  CIFAR-10/CIFAR-100 real archive SHA coverage plus binary-batch parser
  coverage, California Housing real archive SHA coverage plus regression-row
  parser coverage, Tiny ImageNet real archive SHA coverage plus zip/JPEG
  materialization coverage, the substrate-backed train-step smoke for every
  canonical SL architecture, and device-backed regression convergence through
  oneDNN. The live MNIST case remains fail-closed on missing live
  publication/staged bytes, but its real-data path now trains and evaluates
  through the same architecture/device runtime as `jitml train`.
- `docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`
  passed 28 / 28.
- `docker compose run --rm jitml cabal test jitml-sl-canonicals
  --test-options='--pattern=8.12'` passed 9 / 9 after the live linux-cpu cluster
  was bootstrapped and every canonical dataset artifact was staged in MinIO. The
  added live all-row case exercises real staged bytes for MNIST, Fashion-MNIST,
  CIFAR-10, CIFAR-100, Tiny ImageNet, and California Housing through
  `JitML.SL.Architecture` / `JitML.SL.Regression` on the linux-cpu
  `MlpDevice`.
- `docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu`
  passed 24 / 24 with the current live publication and staged dataset set. The
  live MNIST convergence case clears the unchanged threshold using a 60-epoch
  architecture/device budget, and the live all-row staged-byte train/eval smoke
  still passes.
- `docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`
  passed 28 / 28 after the SL live-gate fix.
- A focused disposable-container `spago test` for `web/` passed 9 / 9 while
  fixing the typed RL browser contract parser; the authoritative project-image
  bundle build above also compiled the same PureScript surface warning-clean.

### Remaining Work

None on the Phase `8` framework/runtime surface. Phase `13` owns the full
cross-model median-convergence, checkpoint, reload, and inference matrix that
consumes this all-row SL runtime. Phase `14` owns browser replay controls and
Playwright assertions over the typed RL animation/replay payloads. The legacy
Dense-only compatibility helper is tracked for Phase `13` cleanup in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md#pending-removal).

## Doctrine Sections Cited

- [../README.md → CLI command topology, typed](../README.md#cli-command-topology-typed) (Sprints 8.2, 8.5 — `jitml train` and `jitml rl *` command leaves)
- [../README.md → Plan / Apply commands](../README.md#doctrine-scope) (Sprints 8.2, 8.5, 8.6 — current dry-run / plan-file surfaces)
- [../README.md → At-Least-Once Event Processing](../README.md#doctrine-scope) (Sprints 8.2, 8.6 — payload-hash deduplication helper)
- [../README.md → Test-suite stanzas](../README.md#test-suite-stanzas) (Sprints 8.1, 8.3, 8.4 — dedicated local `jitml-sl-canonicals` and `jitml-rl-canonicals` bodies)
- [../README.md → GADT-Indexed State Machines](../README.md#doctrine-scope) (Sprint 8.7 — `RLRunLifecycle` joins `TrainingLifecycle` and `TuneSweepLifecycle` as phase-indexed singleton GADTs)
- [../README.md → Canonical reinforcement learning environments](../README.md#canonical-reinforcement-learning-environments) (Sprints 8.8 / 8.9 — optional `atari-subset` ROM policy plus copyright-free `KeyDoorGrid-v0` default demo replacement)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/training_workloads.md` — SL canonical
  summaries, RL algorithm metadata hooks, registered real-environment rollout
  helper, `jitml train` / `jitml rl train` summary surfaces, and the
  command-envelope render/parse surfaces plus the `RLRunLifecycle` GADT
  bound to `src/JitML/RL/Framework.hs` after Sprint 8.7; Sprint `8.8`
  records the ALE ROM policy, runtime-loaded Haskell boundary, static C/C++
  shim removal, and `atari-subset` stub retirement gate; Sprint `8.9` records the
  copyright-free `KeyDoorGrid-v0` replacement for default visual RL demos.
- `documents/engineering/jit_codegen_architecture.md` — JIT
  source-generation rule, cache/materialization boundary, and no checked-in
  native adapter source.
- `documents/engineering/code_quality.md` — static-JIT-source lint behavior and
  the absence of any checked-in foreign-source allowlist.
- `documents/engineering/unit_testing_policy.md` — `KeyDoorGrid-v0`
  validation owns required visual discrete-control coverage; `atari-subset`
  smoke remains optional/manual, requires generated/external adapter support,
  and is never required for canonical demo closure.
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

## Sprint 8.13: Real SL Loss, Validation-Driven Selection, and Convergence+Performance Metrics [✅ Done]

**Status**: ✅ Done (reopened + re-closed 2026-06-24) — the foundation sprint every
consumer (Phases 9/10/13/14) needs, so every dependent `Blocked by` edge points down to
this sprint (rule M(a)). **Validated on both lanes: `jitml test jitml-sl-canonicals
--apple-silicon` 24/24 (real host Metal device) and `--linux-cpu` 24/24 (real oneDNN);
`jitml docs check: ok`; `jitml check-code` green in the `jitml:local` image build.**

**Implementation**: `src/JitML/SL/Architecture.hs`
(`SlRunMetrics`, `crossEntropyArchitectureWithDevice`,
`trainArchitectureWithDeviceSelected`), `src/JitML/App.hs` (`TrainingMetrics`,
`splitTrainValidation`, the three rewritten SL training runners + both training-event
publishers), `documents/engineering/training_metrics_and_splits.md`,
`test/sl-canonicals/Main.hs` (the real-metric device test).

**Dependencies**: none (foundation).

Supervised learning now reports real metrics and uses the held-out partitions
correctly, establishing the shared convergence-and-performance metric vocabulary:

- `trainArchitectureWithDeviceSelected` carves a held-out validation slice
  (`splitTrainValidation`, never folded into the gradient-update set), trains epoch
  by epoch, measures the held-out validation cross-entropy after each epoch, and
  returns the **lowest-validation-loss snapshot** — model **selection / early-stop on
  the validation partition**. The `test` partition stays the held-out final metric
  (`evaluateTestSplitDevice` / archive `TestSplit`), reported once on the selected
  model. Datasets whose canonical archive ships no separate validation partition
  (CIFAR-10/100) get an honest held-out slice carved from train, never test-as-validation.
- The faked SL "loss" (`1 − reportedAcc`; `ecValidationLoss = finalLoss`) is gone:
  `publishWorkerTrainingEvent` / `publishTrainingEpoch` now publish
  `ecLoss = tmTrainLoss` (real mean softmax cross-entropy via
  `crossEntropyArchitectureWithDevice`) and `ecValidationLoss = tmValidationLoss`
  (real held-out CE). Regression publishes the real train + held-out validation MSE
  (`meanSquaredErrorWithDevice`).
- A **non-wall-clock SL throughput performance metric** (`slmExamplesProcessed`
  = train examples × epochs) is computed and surfaced on the `jitml train` stdout line
  (`train_loss=… val_loss=… examples_processed=… test_acc=…`); it is deterministic, so
  it stays inside the determinism contract that excludes wall-clock timing.
- `documents/engineering/training_metrics_and_splits.md` is authored and registered
  (the SSoT for the train/test/validation methodology + SL/RL
  convergence-and-performance definitions).

### Exit Definition

- SL training selects on the validation partition; `test` is reported only as the
  held-out final metric; the published loss is a real CE/MSE value, not `1 − accuracy`. ✅
- An SL throughput performance metric is computed and surfaced. ✅
- `training_metrics_and_splits.md` exists, registered, with the convergence+performance
  definitions; Exit Definition item 6 carries the new performance clause. ✅

### Validation

- `jitml test jitml-sl-canonicals --apple-silicon`: **24/24 PASS** — the new
  "real SL metrics: validation-driven selection, real CE loss, throughput (Sprint 8.13)"
  case runs on the real host Metal device, asserting the published loss is a real
  cross-entropy below the `log(numClasses)` random baseline, a finite held-out
  validation loss, the deterministic throughput count, and that a fresh device
  cross-entropy reproduces the published train loss.
- `jitml test jitml-sl-canonicals --linux-cpu`: **24/24 PASS** — the same real-metric
  case runs on the real oneDNN device in the `jitml:local` container.
- `jitml docs check: ok`; `jitml check-code` green during the `jitml:local` image build.

### Remaining Work

- None. ✅

## Sprint 8.14: Fixed-Budget Training Witness and Inference-Ineligible Partial Models [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Training/Budget.hs`,
`src/JitML/SL/Architecture.hs`, `src/JitML/RL/Framework.hs`,
`src/JitML/App.hs`, `src/JitML/Checkpoint/Format.hs`,
`src/JitML/Checkpoint/Store.hs`, `src/JitML/Work/Envelope.hs`
**Docs to update**: `../documents/engineering/training_metrics_and_splits.md`,
`../documents/engineering/training_workloads.md`,
`../documents/engineering/checkpoint_format.md`, `system-components.md`

### Objective

Represent learning completion as pure data. A model has a fixed, reproducible,
terminating `TrainingBudget`; completing that budget mints a `CompletedTraining`
witness. There is no pure value that can represent inference with random,
untrained, smoke-only, cancelled, skipped, or partially trained weights.

### Deliverables

- Define the shared `TrainingBudget` vocabulary for SL epochs, RL environment
  steps, AlphaZero self-play generations, and tuning trials.
- Define `CompletedTraining` as the only constructor path from a completed
  budget plus metric observations to checkpoint eligibility.
- Thread the witness through SL/RL/tuning event payloads without permitting
  inference surfaces to consume raw manifests or raw weights.
- Remove or quarantine existing direct inference paths that can bypass the
  completion witness.

### Validation

- `docker compose run --rm jitml jitml test jitml-unit --linux-cpu`
- `docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu`
- `docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`
- `docker compose run --rm jitml jitml docs check`

### Current Validation State

- `docker compose run --rm jitml cabal test jitml-unit --test-show-details=direct`
  passed **224 / 224**.
- `docker compose run --rm jitml cabal test jitml-sl-canonicals jitml-rl-canonicals --test-show-details=direct`
  passed `jitml-sl-canonicals` **24 / 24** and `jitml-rl-canonicals`
  **31 / 31**.
- The wrapper form `docker compose run --rm jitml cabal run jitml -- test jitml-unit --linux-cpu`
  now passes and reports `jitml-unit: PASS` with **224 / 224** tests.
- `docker compose run --rm jitml cabal run jitml -- test jitml-sl-canonicals --linux-cpu`
  passed through the project wrapper with **24 / 24** tests.
- `docker compose run --rm jitml cabal run jitml -- test jitml-rl-canonicals --linux-cpu`
  passed through the project wrapper with **31 / 31** tests.
- `docker compose run --rm jitml cabal run jitml -- docs check` passed
  (`docs check: ok`).
- `docker compose run --rm jitml cabal run jitml -- check-code` passed
  (`check-code: ok`).
- `docker compose run --rm jitml cabal test jitml-sl-canonicals --test-show-details=direct`
  passed **24 / 24** after `CheckpointDone` gained the optional
  `CompletedTraining` witness in both text and proto event payloads.
- `docker compose run --rm jitml cabal test jitml-rl-canonicals --test-show-details=direct`
  passed **31 / 31** after `CheckpointDoneRL` gained the optional
  `CompletedTraining` witness in both text and proto event payloads.
- `docker compose run --rm jitml cabal test jitml-hyperparameter --test-show-details=direct`
  passed **16 / 16** after `SweepDone` gained the optional
  `CompletedTraining` witness and live tune sweep-done publishers populate it.
- `docker compose run --rm jitml cabal test jitml-rl-canonicals --test-show-details=direct`
  passed **31 / 31** after the worker RL runtime began writing final
  checkpoints under the daemon experiment hash, using RL environment-step budget
  units, publishing `MetricUpdate` convergence rows, and emitting
  `CheckpointDoneRL` with the same `CompletedTraining` witness.
- `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  compiled the new live daemon assertion and passed all **52** non-live cases;
  the **19** live cases failed fast because no `.build/runtime/cluster-publication.json`
  is present.
- `docker compose run --rm jitml cabal test jitml-sl-canonicals --test-show-details=direct`
  passed **24 / 24** after successful SL training began carrying flattened
  trained weights, writing a supervised checkpoint, and emitting `CheckpointDone`
  with `CompletedTraining` from worker and host-Apple training paths.
- `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  was rerun after the SL checkpoint producer change; it passed all **52**
  non-live cases and failed only the expected **19** no-cluster live cases.
- `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  passed **53** non-live cases after adding the checkpoint-browser selector
  negative test: incomplete manifests are omitted from the `CheckpointList`
  summary while completed inference-eligible manifests remain visible. The
  **19** live cases still fail fast without `.build/runtime/cluster-publication.json`.
- `./bootstrap/linux-cpu.sh up` completed the live `linux-cpu` rollout
  (**111** steps) and wrote `.build/runtime/cluster-publication.json`.
- `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  then passed **72 / 72** against the bootstrapped `linux-cpu` cluster. The
  live RL dispatch case observes `EpisodeDone`, `MetricUpdate
  median_final_reward`, and `CheckpointDoneRL completed-training` through
  Pulsar/MinIO; the broader live stanza also revalidated SL dispatch, live
  inference, tuning, GC, TensorBoard sidecars, and AlphaZero checkpoint
  round-trip.
- `docker compose run --rm jitml jitml test all --live --linux-cpu` passed the
  aggregate lane with **8 / 8** stanzas green, including `jitml-unit` **224 / 224**,
  `jitml-sl-canonicals` **24 / 24**, `jitml-rl-canonicals` **31 / 31**,
  `jitml-hyperparameter` **16 / 16**, `jitml-daemon-lifecycle` **32 / 32**,
  `jitml-e2e` **23 / 23**, `jitml-integration` **72 / 72**, and
  `jitml-backends` **23 / 23** on the real `linux-cpu` lane.

### Remaining Work

- None.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../README.md](../README.md)

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
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Stand up the current local supervised-learning and RL framework
> surfaces — canonical SL summaries, RL catalog/environment metadata,
> deterministic trajectory helpers, command summaries, and run-plan metadata —
> while keeping daemon-backed training loops, real datasets, buffers,
> callbacks, GAE, target networks, and live Pulsar events explicit as target
> runtime work.

## Phase Status

🔄 **Active**. The phase owns the framework half of
[Exit Definition](README.md#exit-definition) item 6 (`jitml train` and
`jitml rl train` run the full SL/RL workloads, with golden tests for SL
convergence and RL trajectories under `jitml test all`). **Met today**:
Sprint `8.5` closed the typed framework metadata catalog (schedules,
action distributions, action noise, target networks, GAE, callbacks,
evaluator); Sprint `8.7` closed the `RLRunLifecycle` GADT retrofit.
**Unmet today**: Sprints `8.1`–`8.6` owe real dataset loaders, real SL
training loops, real RL environment stepping, real Policy/VecEnv/replay
buffers, real proto bindings, and the live `training.command` /
`training.event` / `rl.command` / `rl.event` Pulsar round-trips. Detailed
remaining work lives in each sprint's `### Remaining Work` block below.

### Current Implementation Scope

The worktree implements deterministic catalog summaries: eleven canonical
SL problem cells with synthetic convergence curves in
`src/JitML/SL/Canonicals.hs`; the `jitml train` / `jitml eval` command
summaries; the RL command summaries; and deterministic trajectory helpers
in `src/JitML/RL/Algorithms.hs`. It does not yet implement real dataset
loaders, SL/RL training loops, RL environment stepping, replay buffers,
or live Pulsar event publication — those land in the sprints' `###
Remaining Work` blocks below.

## Phase Summary

This phase delivers SL plus the RL *framework*. Phase `9` builds on these
primitives to deliver the algorithm catalog, AlphaZero, and tuning. Splitting
the work this way lets RL framework changes settle before fourteen algorithm
implementations consume them.

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
- `Train.hs`, `Loop.hs`, `Dataset.hs`, live Pulsar training events, and real
  datasets are not present in the current tree.

### Validation

1. `cabal test jitml-sl-canonicals` exercises the eleven-cell canonical
   summary body.
2. `jitml train experiments/mnist.dhall` renders the deterministic
   summary from `src/JitML/App.hs`.
3. Live validation (target): a real training run against MNIST hits the
   canonical convergence threshold, the trained checkpoint round-trips,
   and the committed golden curve under `test/golden/sl/mnist/` matches
   bit-for-bit on the determinism-contract substrate.

### Remaining Work

- Implement `src/JitML/SL/Dataset.hs` (real dataset loader against MinIO
  bucket `jitml-datasets` with SHA-256 verification from the experiment
  Dhall).
- Implement `src/JitML/SL/Loop.hs` (typed training pipeline backed by the
  `TrainingLifecycle` GADT) plus `src/JitML/SL/Train.hs`
  (`train :: TrainingConfig -> ReaderT Env IO TrainResult`).
- Commit golden convergence fixtures under
  `test/golden/sl/<problem-key>/` for every canonical cell.
- Add the live SL convergence assertion to `jitml-sl-canonicals` (Sprint
  `12.3`).

## Sprint 8.2: `jitml train` Local CLI Summary 🔄

**Status**: Active
**Implementation**: `src/JitML/App.hs`, `src/JitML/Plan/Plan.hs`
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
- `proto/jitml/training.proto`, generated Haskell protobuf bindings, and a
  GADT-indexed training lifecycle are not present in the current tree.

### Validation

1. `jitml train --dry-run experiments/mnist.dhall` emits the typed plan
   and exits `0`.
2. `jitml train experiments/mnist.dhall` prints the deterministic
   canonical-problem summary.
3. Live validation (target): `jitml train` resolves and SHA-hashes the
   experiment Dhall, reconciles prerequisites, materializes the dataset,
   publishes `StartTraining` on `training.command.<mode>`, the daemon's
   `TrainingHandler` consumes it, and the resulting
   `training.event.<mode>` envelopes drive the report card.

### Remaining Work

- Add `proto/jitml/training.proto` and generate Haskell protobuf bindings.
- Add the GADT-indexed training lifecycle binding the `jitml train` →
  daemon flow (`Loaded → Ready → Stepping → Evaluating → Checkpointing →
  Finished`).
- Implement the daemon-side `TrainingHandler` that consumes
  `training.command.<mode>` and publishes `training.event.<mode>` through
  the `RetryPolicy` boundary.
- Add the integration test that exercises one real publish → consume
  round-trip behind `JITML_LIVE_E2E=1`.

## Sprint 8.3: RL Catalog Hook for Canonical Tests 🔄

**Status**: Active
**Implementation**: `src/JitML/RL/Algorithms.hs`,
`src/JitML/RL/Environments.hs`,
`test/rl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Land the current local RL catalog and canonical environment hook used by the
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
- Full simulator bindings, render frames, and daemon-backed environment stepping
  remain target runtime validation.

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
  lunar-lander, and atari-subset.
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
- `algorithmCatalog` contains the current local metadata rows consumed by the
  CLI and tests.
- `src/JitML/RL/Framework.hs` defines the local `TrainingLifecycle`,
  `TuneSweepLifecycle`, and (after Sprint 8.7) `RLRunLifecycle` GADT
  lifecycle surfaces plus the matching `rlRunPlan`.
- Runtime `Policy`, `VecEnv`, replay/rollout buffers, and `Async` write
  discipline remain target runtime validation.

### Validation

1. `cabal test jitml-rl-canonicals` verifies the algorithm catalog
   contains representative expected algorithms.
2. `jitml-unit` verifies the run-plan rendering.
3. Live validation (target): real `Policy`, `VecEnv`, replay/rollout
   buffers, and `Async` write discipline are exercised end-to-end against
   running environments through the daemon.

### Remaining Work

- Implement the runtime `Policy` carrying typed action distribution
  shape, parameter references, and the substrate-bound `KernelHandle`
  for inference.
- Implement `VecEnv` for parallel environment stepping.
- Implement replay/rollout buffers with deterministic insertion + sample
  ordering.
- Wire `Async` write discipline so MinIO transcript writes do not block
  the env loop.

## Sprint 8.5: RL CLI Summaries and Report Hooks 🔄

**Status**: Active
**Implementation**: `src/JitML/RL/Algorithms.hs`,
`src/JitML/RL/Framework.hs`,
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
- `proto/jitml/rl.proto` and live Pulsar codecs remain target runtime
  validation.

### Validation

1. `jitml rl train --dry-run experiments/cartpole.dhall` emits the typed
   plan.
2. `jitml rl rollout --seed 42` prints a deterministic trajectory.
3. `jitml-unit` verifies the framework catalog and run-plan surface.
4. Live validation (target): `jitml rl train` publishes `StartRLRun` on
   `rl.command.<mode>`; the daemon's `RlHandler` consumes it, runs the
   real RL loop, and publishes `rl.event.<mode>` envelopes
   (`EpisodeDone`, `EvalDone`, `CheckpointDone`, `MetricUpdate`) that
   round-trip into the report card.

### Remaining Work

- Add `proto/jitml/rl.proto` and the generated Haskell protobuf bindings.
- Implement the live Pulsar codecs that translate between the protobuf
  envelopes and the typed framework values.
- Implement the daemon-side `RlHandler` that consumes
  `rl.command.<mode>` and emits `rl.event.<mode>` through the
  `RetryPolicy` boundary.
- Add the live integration test that round-trips one `StartRLRun` →
  `EpisodeDone` cycle behind `JITML_LIVE_E2E=1`.

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
- `RLLoop`, `runRLLoop`, `RLConfig`, and daemon-backed training execution are
  not implemented in the current tree.

### Validation

1. `jitml rl train --dry-run experiments/cartpole.dhall` emits the typed
   plan.
2. `jitml rl train experiments/cartpole.dhall` prints the algorithm
   catalog summary.
3. Live validation (target): a real `RLLoop` executes against the daemon
   for one cartpole episode, reaches the reward threshold, and the
   resulting checkpoint resumes bit-deterministically to the same reward.

### Remaining Work

- Implement `src/JitML/RL/Loop.hs` (`RLLoop`, `runRLLoop`, `RLConfig`)
  backed by the `RLRunLifecycle` GADT from Sprint `8.7`.
- Plumb the loop through the daemon's `RlHandler` and verify it consumes
  the per-domain dedup cache, checkpoints to MinIO, and emits live
  `rl.event.<mode>` envelopes.
- Add the live reward-threshold + checkpoint/resume equality assertion to
  `jitml-rl-canonicals` (Sprint `12.4`).


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

- [../HASKELL_CLI_TOOL.md → Command Topology](../HASKELL_CLI_TOOL.md) (Sprints 8.2, 8.5 — `jitml train` and `jitml rl *` command leaves)
- [../HASKELL_CLI_TOOL.md → Plan / Apply](../HASKELL_CLI_TOOL.md) (Sprints 8.2, 8.5, 8.6 — current dry-run / plan-file surfaces)
- [../HASKELL_CLI_TOOL.md → At-Least-Once Event Processing](../HASKELL_CLI_TOOL.md) (Sprints 8.2, 8.6 — local payload-hash deduplication helper)
- [../HASKELL_CLI_TOOL.md → Test Organization](../HASKELL_CLI_TOOL.md) (Sprints 8.1, 8.3, 8.4 — dedicated local `jitml-sl-canonicals` and `jitml-rl-canonicals` bodies)
- [../HASKELL_CLI_TOOL.md → GADT-Indexed State Machines](../HASKELL_CLI_TOOL.md) (Sprint 8.7 — `RLRunLifecycle` joins `TrainingLifecycle` and `TuneSweepLifecycle` as phase-indexed singleton GADTs)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/training_workloads.md` — current local SL canonical
  summaries, RL algorithm metadata hooks, deterministic trajectory helper,
  `jitml train` / `jitml rl train` summary surfaces, and the
  `RLRunLifecycle` GADT bound to `src/JitML/RL/Framework.hs` after Sprint
  8.7; target training loops and environment runtime work.
- `documents/engineering/daemon_architecture.md` — local payload-hash
  deduplication helper; target at-least-once `TrainingHandler` and `RlHandler`.
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
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)

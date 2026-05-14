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

> **Purpose**: Stand up supervised learning training loops with the canonical SL
> problem set and golden convergence curves, the canonical RL environment set,
> and the typed RL framework primitives — Algorithm class taxonomy at the type
> level, Policy as typed value, Environment / VecEnv as typed capability,
> replay/rollout buffers with `Async` write discipline, schedules, action
> distributions, action noise, target networks + Polyak averaging, GAE,
> callbacks, multi-sink Logger, Evaluator, training loops as typed pipelines.

## Phase Status

⏸️ **Blocked** on Phase `7` closure. Both SL and RL workloads compile their
kernels through the JIT codegen drivers (Phase `7`) and run on the daemon
(Phase `5`).

## Phase Summary

This phase delivers SL plus the RL *framework*. Phase `9` builds on these
primitives to deliver the algorithm catalog, AlphaZero, and tuning. Splitting
the work this way lets RL framework changes settle before fourteen algorithm
implementations consume them.

## Sprint 8.1: Supervised Training Loop and Canonical SL Problems ⏸️

**Status**: Blocked
**Blocked by**: phase-7
**Implementation**: `src/JitML/SL/Train.hs`, `src/JitML/SL/Loop.hs`,
`src/JitML/SL/Problems/Mnist.hs`, `src/JitML/SL/Problems/Cifar.hs`,
`src/JitML/SL/Problems/Imagenet.hs`, `src/JitML/SL/Dataset.hs`,
`test/golden/sl/`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Stand up the supervised training loop, the canonical SL problem set (MNIST,
Fashion-MNIST, CIFAR-10, CIFAR-100, ImageNet), the dataset loader against
MinIO bucket `jitml-datasets`, and golden convergence-curve fixtures.

### Deliverables

- `Train.hs` exposes `train :: TrainingConfig -> ReaderT Env IO TrainResult`,
  `TrainingConfig` carrying the resolved-Dhall + numerical-core graph + data
  loader + optimizer + scheduler + loss + callbacks.
- `Loop.hs` is the typed pipeline (per doctrine `GADT-Indexed State
  Machines`): `TrainingLifecycle Loaded`, `TrainingLifecycle Ready`,
  `TrainingLifecycle Stepping`, `TrainingLifecycle Evaluating`,
  `TrainingLifecycle Checkpointing`, `TrainingLifecycle Finished`.
- `Dataset.hs` lazily fetches pinned source datasets from MinIO bucket
  `jitml-datasets`; SHA-256 verified against the experiment Dhall.
- Per-problem modules under `src/JitML/SL/Problems/` declare:
  - dataset URL + SHA-256,
  - threshold methodology (target accuracy / loss with tolerance band),
  - golden curve fixture path under `test/golden/sl/<problem>/curve.cbor`.
- The `MetricUpdate` and `EpochDone` events are published on
  `training.event.<mode>` (Sprint `8.2`).

### Validation

1. `jitml train experiments/sl/mnist-baseline.dhall` reaches the threshold
   accuracy under `SL_EPOCHS` from
   [system-components.md → POC Report-Card
   Knobs](system-components.md#poc-report-card-knobs).
2. The convergence curve matches the golden fixture under same-substrate
   determinism (per-step loss / per-epoch eval-accuracy bit-identical).
3. The Pulsar event stream from `training.event.<mode>` reflects every
   `EpochDone` with the metric snapshot.

## Sprint 8.2: `jitml train` CLI and `training.command.<mode>` / `training.event.<mode>` ⏸️

**Status**: Blocked
**Blocked by**: 8.1, 5.5
**Implementation**: `src/JitML/CLI/Commands/Train.hs`,
`src/JitML/Service/TrainingHandler.hs`,
`proto/jitml/training.proto`
**Docs to update**: `documents/engineering/training_workloads.md`,
`documents/engineering/daemon_architecture.md`

### Objective

Wire `jitml train` (Plan/Apply with `--dry-run` and `--plan-file`) into the
CLI as the operator-facing entrypoint, and the `training.command.<mode>` /
`training.event.<mode>` Pulsar topic family as the daemon's I/O.

### Deliverables

- `jitml train <experiment-dhall>` plan steps:
  1. Resolve and SHA-hash the experiment Dhall.
  2. Reconcile prerequisites; dataset materialised in `jitml-datasets`.
  3. Publish `StartTraining` envelope on `training.command.<mode>`.
  4. Subscribe to `training.event.<mode>` and stream events to stdout (or
     write structured JSON when `--format json`).
- `proto/jitml/training.proto` declares `StartTraining`, `StopTraining`,
  `ResumeFromCheckpoint`, `AbortTraining`, `StepDone`, `EpochDone`,
  `EvalDone`, `CheckpointDone`, `MetricUpdate`, `TrainingFinished`,
  `TrainingFailed`. `proto-lens` generates Haskell bindings.
- `src/JitML/Service/TrainingHandler.hs` is the daemon's at-least-once
  consumer for `training.command.<mode>` (Sprint `5.5`).
- The training lifecycle ADT is GADT-indexed per doctrine `GADT-Indexed
  State Machines`.

### Validation

1. `jitml train --dry-run experiments/sl/mnist-baseline.dhall` emits the
   typed plan and exits `0`.
2. `jitml train experiments/sl/mnist-baseline.dhall` produces the same
   convergence curve as Sprint `8.1`'s direct invocation.
3. Replay of the same `StartTraining` envelope is idempotent (Sprint `5.5`'s
   `EventID` deduplication holds).

## Sprint 8.3: Canonical RL Environments ⏸️

**Status**: Blocked
**Blocked by**: phase-7
**Implementation**: `src/JitML/Env/`, `src/JitML/Env/CartPole.hs`,
`src/JitML/Env/MountainCar.hs`, `src/JitML/Env/LunarLander.hs`,
`src/JitML/Env/AtariSubset.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Land the canonical RL environments: `CartPole-v1`, `MountainCar-v0`,
`LunarLander-v2`, plus a small Atari subset (`Pong`, `Breakout`,
`SpaceInvaders`).

### Deliverables

- Each environment is an in-process Haskell implementation; no external
  Python or Gym dependency.
- Typed `EnvObs`, `EnvAction`, `EnvReward`, `EnvDone` per environment.
- Each env supports `reset :: Seed -> IO EnvState`, `step :: EnvState ->
  EnvAction -> IO (EnvObs, EnvReward, EnvDone, EnvInfo)`,
  `render :: EnvState -> IO RenderFrame` (RenderFrame is a typed payload
  consumed by the PureScript trajectory panel in Phase `11`).
- Per-environment seed derivation is deterministic.

### Validation

1. Deterministic-seed reset+step sequences are bit-identical across runs.
2. Each environment passes a property test against expected reward bounds.

## Sprint 8.4: RL Framework Primitives ⏸️

**Status**: Blocked
**Blocked by**: 8.3
**Implementation**: `src/JitML/RL/Algorithm.hs`, `src/JitML/RL/Policy.hs`,
`src/JitML/RL/Env.hs`, `src/JitML/RL/Buffer.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Stand up the typed RL framework primitives consumed by the algorithm catalog
in Phase `9`: Algorithm class taxonomy at the type level, Policy as typed
value, Environment / VecEnv as typed capability, replay/rollout buffers with
`Async` write discipline.

### Deliverables

- `Algorithm` class taxonomy as a GADT-indexed kind (`OnPolicy`,
  `OffPolicy`, `Hierarchical`, `Recurrent`, `MaskingCapable`,
  `ContinuousAction`, `DiscreteAction`, `ImageObs`, `VectorObs`). The
  taxonomy is used at the type level to constrain algorithm-instance
  declarations.
- `Policy` ADT carrying the typed action distribution shape, parameter
  references, and the substrate-bound `KernelHandle` for inference.
- `Environment` typeclass and `VecEnv` parallel-environment combinator.
- `Buffer` carries the replay buffer (off-policy) and rollout buffer
  (on-policy) shapes; writes are `Async` with backpressure per
  [../README.md → Replay-buffer write discipline under Async](../README.md#replay-buffer-write-discipline-under-async).
- `RLRunLifecycle` GADT mirrors the SL `TrainingLifecycle` shape.

### Validation

1. `jitml-unit` exercises the type-level Algorithm taxonomy via golden
   inhabitation tests.
2. `jitml-integration` exercises the `Async` buffer-write discipline under
   synthetic backpressure.

## Sprint 8.5: Schedules, Distributions, Noise, Target Networks, GAE, Callbacks, Logger, Evaluator ⏸️

**Status**: Blocked
**Blocked by**: 8.4
**Implementation**: `src/JitML/RL/Schedule.hs`,
`src/JitML/RL/Distribution.hs`, `src/JitML/RL/Noise.hs`,
`src/JitML/RL/Target.hs`, `src/JitML/RL/GAE.hs`,
`src/JitML/RL/Callback.hs`, `src/JitML/RL/Logger.hs`,
`src/JitML/RL/Eval.hs`,
`src/JitML/CLI/Commands/RlRun.hs`,
`proto/jitml/rl.proto`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Land the per-component primitives used by every algorithm in the Phase `9`
catalog: schedules, action distributions, action noise, target networks +
Polyak averaging, GAE, callbacks as composable hooks, multi-sink Logger,
Evaluator. Wire `jitml rl run` and the `rl.command.<mode>` /
`rl.event.<mode>` Pulsar topics.

### Deliverables

- `Schedule` ADT (`ConstantSched`, `LinearSched`, `ExponentialSched`,
  `PiecewiseSched`).
- `ActionDistribution` ADT (`Categorical`, `Gaussian`, `Bernoulli`,
  `MaskedCategorical`, `MixtureGaussian`).
- `ActionNoise` ADT (`Gaussian`, `OrnsteinUhlenbeck`,
  `ParameterSpaceNoise`).
- `TargetNetwork`: typed Polyak-averaging step `polyak :: Double -> Params
  -> Params -> Params` plus periodic-copy mode.
- `GAE :: GAEParams -> Trajectory -> Advantages` deterministic.
- `Callback` is a typed composable hook with `onStepEnd`, `onEpisodeEnd`,
  `onCheckpoint` events.
- `Logger` is a multi-sink (TensorBoard + Pulsar `rl.event.<mode>` +
  Prometheus + stdout when `--format plain`).
- `Evaluator` runs `RL_EVAL_EPISODES` (see [system-components.md → POC
  Report-Card Knobs](system-components.md#poc-report-card-knobs))
  deterministic eval episodes against the trained policy.
- `proto/jitml/rl.proto` declares `StartRLRun`, `StopRLRun`, `EpisodeDone`,
  `EvalDone`, `CheckpointDone`, `MetricUpdate`.
- `jitml rl run <rl-experiment-dhall>` is Plan/Apply.

### Validation

1. Each primitive has a `decode . encode == id` golden.
2. `jitml-unit` exercises GAE against a synthetic trajectory and asserts
   bit-identical advantage arrays.
3. `jitml rl run --dry-run` emits the typed plan.

## Sprint 8.6: RL Training Loops as Typed Pipelines ⏸️

**Status**: Blocked
**Blocked by**: 8.5
**Implementation**: `src/JitML/RL/Loop.hs`,
`src/JitML/Service/RlHandler.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Compose the framework primitives into typed RL training pipelines that the
algorithm catalog (Phase `9`) plugs into.

### Deliverables

- `RLLoop` GADT carrying the `RLRunLifecycle` indices and the per-stage
  combinators (`collectRollout`, `optimisePolicy`, `optimiseValue`,
  `updateTarget`, `evaluate`, `checkpoint`).
- `runRLLoop :: HasEngine env => RLConfig -> ReaderT Env IO RLResult` is
  the daemon's entrypoint into the loop.
- `src/JitML/Service/RlHandler.hs` is the at-least-once consumer for
  `rl.command.<mode>` (Sprint `5.5`).

### Validation

1. `jitml rl run experiments/rl/cartpole-ppo-baseline.dhall` reaches the
   threshold mean episode reward inside `RL_STEPS` (see
   [system-components.md → POC Report-Card
   Knobs](system-components.md#poc-report-card-knobs)).
2. The daemon's at-least-once `RlHandler` re-applies a duplicated
   `StartRLRun` envelope idempotently.

## Doctrine Sections Cited

- [../HASKELL_CLI_TOOL.md → GADT-Indexed State Machines](../HASKELL_CLI_TOOL.md) (Sprints 8.1, 8.4, 8.6)
- [../HASKELL_CLI_TOOL.md → Plan / Apply](../HASKELL_CLI_TOOL.md) (Sprints 8.2, 8.5)
- [../HASKELL_CLI_TOOL.md → At-Least-Once Event Processing](../HASKELL_CLI_TOOL.md) (Sprints 8.2, 8.6)
- [../HASKELL_CLI_TOOL.md → Capability Classes and Service Errors](../HASKELL_CLI_TOOL.md) (Sprints 8.1, 8.5 — `HasMinIO`/`HasPulsar` consumers)
- [../HASKELL_CLI_TOOL.md → Generated Artifacts](../HASKELL_CLI_TOOL.md) (Sprints 8.2, 8.5 — generated proto bindings)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/training_workloads.md` — populate the SL training
  loop, canonical SL problem set with thresholds, RL framework primitive
  catalog, and the `jitml train` / `jitml rl run` CLI surface.
- `documents/engineering/daemon_architecture.md` — link to the at-least-once
  `TrainingHandler` and `RlHandler`.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → Training Workload Surfaces` rows (SL loop, RL
  framework primitives, schedules / distributions / noise / target /
  GAE / callbacks / logger / evaluator / loops, canonical environments)
  move from `⏸️ Blocked` through `🔄 Active` to `✅ Done`.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)

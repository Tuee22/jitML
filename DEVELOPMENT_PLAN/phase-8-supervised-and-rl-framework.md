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

✅ **Done** for the local supervised and RL framework surfaces. Both SL and RL
workloads compile their kernels through the target Haskell-owned JIT source
renderers (Phase `7`) and run on the target daemon (Phase `5`) in live
validation.

### Current Implementation Scope

The current worktree implements deterministic local summaries: six canonical SL
problem cells with synthetic convergence curves in `src/JitML/SL/Canonicals.hs`,
the `jitml train` / `jitml eval` command summaries, the RL command summaries,
and deterministic trajectory helpers in `src/JitML/RL/Algorithms.hs`. It does
not yet implement real dataset loaders, SL/RL training loops, RL environment
types, buffers, callbacks, GAE, target networks, or live Pulsar event
publication.

## Phase Summary

This phase delivers SL plus the RL *framework*. Phase `9` builds on these
primitives to deliver the algorithm catalog, AlphaZero, and tuning. Splitting
the work this way lets RL framework changes settle before fourteen algorithm
implementations consume them.

## Sprint 8.1: Local Supervised Canonical Summaries ✅

**Status**: Done
**Implementation**: `src/JitML/SL/Canonicals.hs`,
`test/sl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Stand up the current deterministic supervised-learning catalog summary. Real
dataset loaders, daemon-backed training loops, MinIO dataset access, and the
full eleven-cell canonical matrix remain target runtime work.

### Deliverables

- `src/JitML/SL/Canonicals.hs` declares six current canonical cells:
  `mnist-linear`, `fashion-mnist-cnn`, `cifar10-resnet`,
  `cifar100-resnet`, `tiny-imagenet-attention`, and
  `california-housing-dense`.
- `convergenceCurve` produces a five-point deterministic synthetic loss curve
  from the problem seed.
- `finalLoss` returns the final value from that deterministic curve.
- `test/sl-canonicals/Main.hs` verifies the catalog is populated, curves are
  deterministic, and every final loss improves over the initial loss.
- `Train.hs`, `Loop.hs`, `Dataset.hs`, live Pulsar training events, and real
  datasets are not present in the current tree.

### Validation

1. `cabal test jitml-sl-canonicals` exercises the current local canonical
   summary body.
2. `jitml train experiments/mnist.dhall` renders the deterministic local
   summary from `src/JitML/App.hs`.
3. Live training thresholds and Pulsar events remain target validation.

## Sprint 8.2: `jitml train` Local CLI Summary ✅

**Status**: Done
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

1. `jitml train --dry-run experiments/mnist.dhall` emits the typed plan and
   exits `0`.
2. `jitml train experiments/mnist.dhall` prints the deterministic local
   canonical-problem summary.
3. Protobuf envelope replay remains target validation.

## Sprint 8.3: RL Catalog Hook for Canonical Tests ✅

**Status**: Done
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

1. `cabal test jitml-rl-canonicals` exercises the current catalog and
   deterministic trajectory helper.
2. `jitml-unit` verifies the canonical environment catalog and deterministic
   local step helper.

## Sprint 8.4: RL Metadata Primitives ✅

**Status**: Done
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
  `TuneSweepLifecycle`, and RL run-plan surface.
- Runtime `Policy`, `VecEnv`, replay/rollout buffers, and `Async` write
  discipline remain target runtime validation.

### Validation

1. `cabal test jitml-rl-canonicals` verifies the current algorithm catalog
   contains representative expected algorithms.
2. `jitml-unit` verifies the local run-plan rendering.

## Sprint 8.5: RL CLI Summaries and Report Hooks ✅

**Status**: Done
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

1. `jitml rl train --dry-run experiments/cartpole.dhall` emits the typed plan.
2. `jitml rl rollout --seed 42` prints a deterministic local trajectory.
3. `jitml-unit` verifies the local framework catalog and run-plan surface.

## Sprint 8.6: RL Training Plan Surface ✅

**Status**: Done
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

1. `jitml rl train --dry-run experiments/cartpole.dhall` emits the typed plan.
2. `jitml rl train experiments/cartpole.dhall` prints the local algorithm
   catalog summary.
3. Reward thresholds, checkpoint/resume equality, and daemon execution remain
   target validation.

## Doctrine Sections Cited

- [../HASKELL_CLI_TOOL.md → Command Topology](../HASKELL_CLI_TOOL.md) (Sprints 8.2, 8.5 — `jitml train` and `jitml rl *` command leaves)
- [../HASKELL_CLI_TOOL.md → Plan / Apply](../HASKELL_CLI_TOOL.md) (Sprints 8.2, 8.5, 8.6 — current dry-run / plan-file surfaces)
- [../HASKELL_CLI_TOOL.md → At-Least-Once Event Processing](../HASKELL_CLI_TOOL.md) (Sprints 8.2, 8.6 — local payload-hash deduplication helper)
- [../HASKELL_CLI_TOOL.md → Test Organization](../HASKELL_CLI_TOOL.md) (Sprints 8.1, 8.3, 8.4 — dedicated local `jitml-sl-canonicals` and `jitml-rl-canonicals` bodies)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/training_workloads.md` — current local SL canonical
  summaries, RL algorithm metadata hooks, deterministic trajectory helper, and
  `jitml train` / `jitml rl train` summary surfaces; target training loops and
  environment runtime work.
- `documents/engineering/daemon_architecture.md` — local payload-hash
  deduplication helper; target at-least-once `TrainingHandler` and `RlHandler`.

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

# Phase 13: Linux CUDA and Cluster Closure

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[phase-7-jit-codegen-and-substrates.md](phase-7-jit-codegen-and-substrates.md),
[phase-8-supervised-and-rl-framework.md](phase-8-supervised-and-rl-framework.md),
[phase-9-rl-catalog-alphazero-and-tuning.md](phase-9-rl-catalog-alphazero-and-tuning.md),
[phase-10-checkpointing-and-inference.md](phase-10-checkpointing-and-inference.md),
[phase-11-purescript-frontend-and-demo.md](phase-11-purescript-frontend-and-demo.md),
[phase-12-test-stanzas-and-cross-cluster.md](phase-12-test-stanzas-and-cross-cluster.md),
[phase-14-apple-silicon-closure.md](phase-14-apple-silicon-closure.md),
[phase-15-cross-substrate-and-handoff.md](phase-15-cross-substrate-and-handoff.md),
[../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Close every live-runtime obligation that requires a real Linux
> host with NVIDIA hardware, a running Kind cluster, live Helm subcharts,
> live broker, live MinIO, and a browser. The phase exists because
> Phases `7`–`12` are scoped to code-surface ownership; their
> Linux-CUDA / cluster / broker / MinIO / Playwright obligations migrated
> here so a single Linux/NVIDIA session closes them all.

## Phase Status

🔄 **Active**. The phase owns the cluster + CUDA + browser halves of
[Exit Definition](README.md#exit-definition) items 1 (per-substrate JIT
execution — CUDA side), 3 (live `jitml bootstrap` + Envoy + routes),
6 (live training/RL/tune Plan/Apply), 7 (live MinIO checkpoints + CUDA
production weight loading), 8 (live PureScript panels behind Playwright),
9 (live `jitml-e2e` Pulumi orchestration). Closure requires a single
Linux/NVIDIA machine session with Docker, Kind, Helm, and a routable
NVIDIA RuntimeClass.

**Met today**: nothing under this phase yet. Upstream code surfaces exist
under Phase `7` (CUDA codegen + cuBLAS/cuDNN typed bindings validated
2026-05-24), Phase `5` (daemon scaffold + capability classes + at-least-
once consumer validated against synthetic broker), Phase `12.8` (typed
Pulumi orchestrator + `JitML.Test.LivePlan`), and Phases `8`/`9`/`10`/`11`
(deterministic local summaries + filesystem-backed capability boundaries).

**Unmet today**: every live obligation in the sprint bodies below.

### Current Implementation Scope

The Haskell-side scaffolding for every Sprint in this phase is in place
in the worktree. Each Sprint closes only after its named validation
commands execute on a real Linux/NVIDIA host and pass.

## Phase Summary

Sprints are ordered by execution dependency: bring the cluster up first,
then exercise capability classes against live infrastructure, then layer
on training / RL / tuning / inference / GC, then add real CUDA RL loss
code and AlphaZero with real network priors, then the live frontend
WebSocket proxy and Playwright. Cross-substrate parity that consumes
CUDA outputs lives in Phase `15`.

## Sprint 13.1: Pulumi-Orchestrated Ephemeral Kind + Helm Rollout 🔄

**Status**: Active
**Implementation**: `infra/pulumi/index.ts`, `src/JitML/Test/LivePlan.hs`,
`src/JitML/Bootstrap.hs`, `src/JitML/Cluster/Helm.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`,
`documents/engineering/unit_testing_policy.md`

### Objective

Execute the typed phased Helm rollout against a real ephemeral Kind
cluster via the Pulumi orchestrator. The cluster reaches Ready behind
the real Envoy listener; Pulumi `destroy` cleans the cluster without
orphans. Adopts `Reconcilers: Idempotent Mutation as a Single Command`
from [../README.md](../README.md).

### Deliverables

- `pulumi up` (or the typed `JitML.Test.LivePlan.livePhasedClusterPlan`)
  applied through a real Linux+Docker host brings up
  `jitml-e2e-<short-sha>` Kind cluster, runs `helm dependency build
  chart`, executes the phased rollout (Harbor first → MinIO/Postgres/Pulsar →
  service Postgres → jitml-service → jitml-demo), and the
  `cluster-publication.json` artifact reports all seven publication
  components Ready.
- `pulumi destroy` followed by `pulumi stack rm` leaves no
  `jitml-e2e-*` Kind cluster, no Harbor project, and no leaked Docker
  volume.

### Validation

1. On Linux+Docker+NVIDIA: `JitML.Test.LivePlan.livePhasedClusterPlan`
   executed through the typed `Subprocess` boundary brings the stack up
   under 20 minutes (subchart pulls + Postgres readiness).
2. `kubectl get pods -A` reports every chart pod `Running`/`Ready`.
3. The post-teardown `kind get clusters` lists no `jitml-e2e-`-prefixed
   cluster.

### Remaining Work

- Execute the live phased Helm + Pulsar topic creation rollout against
  a real Kind cluster on Linux+NVIDIA.
- Validate the `cluster-publication.json` shape against the seven
  publication components after live up.
- Validate the teardown leaves no orphan Kind cluster, Harbor project,
  MinIO bucket, or Docker volume on the host.

## Sprint 13.2: Live Capability Class Validation (MinIO + Pulsar + Harbor) 🔄

**Status**: Active
**Blocked by**: Sprint `13.1`
**Implementation**: `src/JitML/Service/MinIOSubprocess.hs`,
`src/JitML/Service/PulsarWebSocketSubprocess.hs`,
`src/JitML/Service/HarborSubprocess.hs`,
`src/JitML/Checkpoint/Store.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`,
`documents/engineering/checkpoint_format.md`

### Objective

Exercise every `HasMinIO` / `HasPulsar` / `HasHarbor` method through the
running cluster: `putBlobIfAbsent` with `If-None-Match: *` returns ETag
on first write and `SEConflict` on subsequent identical PUTs;
`applyPointerWrite` honours `If-Match` and surfaces `412` as
`SEConflict`; `pulsarPublish` / `pulsarConsume` round-trip a payload on
a substrate-scoped topic; `harborPromoteImage` promotes a tag through
the live registry. Closes Exit Definition item 2's live capability slice
and the live MinIO halves of items 7 and 5.

### Deliverables

- A live MinIO conditional-write test asserts both first-write success
  and subsequent-conflict for `putBlobIfAbsent` plus `casPointer`
  through `JitML.Service.MinIOSubprocess`.
- A live Pulsar WebSocket publish/consume test on a substrate-scoped
  topic round-trips a payload and asserts subscription acquisition as
  `jitml-service`.
- A live Harbor tag-promotion test round-trips an image through the
  same-repository promotion path.
- The bucket layout for `jitml-checkpoints/<experiment-hash>/` holds
  blobs/manifests after a controlled write under the live capability
  classes.

### Validation

1. On Linux+Docker+NVIDIA, with the cluster from Sprint `13.1` up: a
   targeted `jitml-integration --test-options='-p Live'` (or equivalent
   bespoke driver) exercises the three capability classes and exits `0`.

### Remaining Work

- Add the live `jitml-integration` cases that drive `HasMinIO`,
  `HasPulsar`, and `HasHarbor` through `JitML.Service.*Subprocess` against
  the running cluster.
- Run them on Linux+NVIDIA against Sprint `13.1`'s cluster and record
  the validation date + host details under each capability section.

## Sprint 13.3: Daemon Training/RL/Tune Handlers on Live Broker 🔄

**Status**: Active
**Blocked by**: Sprint `13.2`
**Implementation**: `src/JitML/Service/Runtime.hs`,
`src/JitML/Service/Consumer.hs`,
`src/JitML/Service/Handlers/Training.hs`,
`src/JitML/Service/Handlers/Rl.hs`,
`src/JitML/Service/Handlers/Tune.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`,
`documents/engineering/training_workloads.md`

### Objective

Bring up the daemon-side `TrainingHandler`, `RlHandler`, and
`TuneHandler` consuming `training.command.<mode>` /
`rl.command.<mode>` / `tune.command.<mode>` through the live Pulsar
broker, dispatching workloads through `daemonWorkloadDispatcher`, and
publishing the corresponding event envelopes. Adopts `At-Least-Once
Event Processing` and `Retry Policy as First-Class Values` from
[../README.md](../README.md).

### Deliverables

- The cluster `jitml-service` pod subscribes to all three command
  topics for its substrate, acks command messages only after the
  workload dispatcher returns success, and republishes redelivered
  messages on failure.
- Each handler emits at least one canonical event envelope per command
  consumed (training: `EpochCompleted`; rl: `EpisodeDone`; tune: a
  `TuneEvent` trial frame).
- The handlers consume the per-domain `DedupCache` so duplicate command
  payloads produce exactly one downstream event per envelope.

### Validation

1. A test driver publishes `StartTraining` / `StartRLRun` / `StartSweep`
   on the substrate-scoped command topics; the live cluster daemon
   consumes each, dispatches the workload, and the corresponding event
   topic carries the expected envelope.
2. A deliberate duplicate-publish on each command topic produces
   exactly one event envelope (dedup proven against the live broker).

### Remaining Work

- Implement `TrainingHandler`, `RlHandler`, `TuneHandler` against live
  `HasPulsar` (handler bodies currently route through the synthetic
  broker in `jitml-daemon-lifecycle`).
- Wire them into `daemonWorkloadDispatcher` so the live cluster service
  pod runs them.
- Validate live publish/consume + dedup against Sprint `13.1`'s cluster.

## Sprint 13.4: Live SL Training E2E with Real Datasets 🔄

**Status**: Active
**Blocked by**: Sprint `13.3`
**Implementation**: `src/JitML/SL/Dataset.hs`, `src/JitML/SL/Loop.hs`,
`src/JitML/App.hs`,
`src/JitML/Service/Handlers/Training.hs`
**Docs to update**: `documents/engineering/training_workloads.md`,
`documents/engineering/checkpoint_format.md`

### Objective

Run a full SL training cell end-to-end through the cluster: a real
dataset object lives in MinIO bucket `jitml-datasets`, `jitml train`
publishes `StartTraining`, the daemon resolves the dataset reference
through `fetchDatasetRef` + `HasMinIO`, runs the deterministic training
pipeline against the real data, and publishes `EpochCompleted` /
`CheckpointDone` events. The live checkpoint round-trips through
`writeCheckpointSnapshotWithMinIO`. Closes Exit Definition item 6's SL
slice.

### Deliverables

- One canonical SL cell (MNIST shallow MLP at minimum) trains
  end-to-end through the live cluster against a real MinIO-staged
  dataset.
- The committed convergence threshold for that cell is met by the live
  measured final loss.
- The trained checkpoint round-trips through MinIO and replays
  bit-deterministically.
- Live-measured convergence fixtures land under
  `test/golden/sl/<problem-key>/curve.txt` and replace (or supplement
  with a `-live.txt` sibling) the current deterministic synthetic curves.
- The live SL convergence assertion added to `jitml-sl-canonicals` (see
  Phase `12` Sprint `12.3`) exercises the live path.

### Validation

1. End-to-end: real MNIST training run drives the daemon path, the
   reported final loss meets the committed threshold, and the
   checkpoint replays bit-deterministically.
2. `cabal test jitml-sl-canonicals --test-options='-p Live'` passes
   against the live cluster.

### Remaining Work

- Wire `JitML.SL.Dataset.fetchDatasetRef` into `jitml train` /
  `TrainingHandler` through `JitML.Service.MinIOSubprocess`.
- Replace local fixture hashes in `canonicalDatasets` with real dataset
  object hashes from experiment Dhall.
- Replace / supplement deterministic synthetic SL goldens with live
  measured convergence fixtures.
- Drive `jitml train` against the remaining ten canonical SL cells once
  the first cell closes.
- Consume `sl_epochs` / `sl_batch` report-card knobs from
  `cabal.project` in the live assertion.

## Sprint 13.5: Real RL Environment Simulators and Daemon Env Loop 🔄

**Status**: Active
**Blocked by**: Sprint `13.3`
**Implementation**: `src/JitML/RL/Environments.hs`,
`src/JitML/RL/Loop.hs`,
`src/JitML/Service/Handlers/Rl.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Replace the deterministic step helper for cartpole / mountain-car /
lunar-lander / atari-subset with real simulator bindings (inline-c
classical control + embedded Box2D + ALE), expose the typed env-step
boundary, and run the daemon-backed environment loop driven by the
Phase `5` Pulsar consumer.

### Deliverables

- Real simulator bindings for `cartpole`, `mountain-car`,
  `lunar-lander`, and `atari-subset`. Classical control physics for
  cartpole + mountain-car may use a pure-Haskell solver; lunar-lander
  uses an embedded Box2D through `inline-c`; atari-subset uses an ALE
  binding.
- `step :: Env -> Action -> IO (Obs, Reward, Done)` exposed through the
  typed boundary, including render-frame access for the demo.
- The daemon-backed environment loop drives `RLLoop.runRLLoop` through
  `RlHandler` against the live broker.

### Validation

1. On Linux: `cabal test jitml-rl-canonicals --test-options='-p
   LiveSimulator'` exercises cartpole + mountain-car at a minimum
   against the real physics.
2. End-to-end: a live `jitml rl train experiments/cartpole.dhall`
   reaches the canonical reward threshold against the real cartpole
   simulator inside the cluster daemon.

### Remaining Work

- Implement the four real simulator bindings.
- Implement the typed `step` boundary plus render access.
- Wire `runRLLoop` through `RlHandler` against the live broker.

## Sprint 13.6: Live RL Training E2E with Per-Cohort Goldens 🔄

**Status**: Active
**Blocked by**: Sprint `13.5`
**Implementation**: `src/JitML/RL/Loop.hs`,
`src/JitML/Service/Handlers/Rl.hs`,
`test/rl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Drive `jitml rl train` against every algorithm × canonical environment
cohort with the real simulators from Sprint `13.5`, commit per-cohort
reward / trajectory goldens, and assert per-seed final-reward
distribution.

### Deliverables

- Live `jitml rl train` runs the full algorithm × env catalog cohort
  inside the cluster daemon.
- `test/golden/rl/<algo>/<env>/trajectory.txt` and
  `test/golden/rl/<algo>/<env>/reward-distribution.txt` are pinned per
  cohort.
- `jitml-rl-canonicals` consumes `rl_steps` / `rl_eval_episodes`
  report-card knobs and asserts per-seed final-reward distribution.

### Validation

1. `cabal test jitml-rl-canonicals --test-options='-p Live'` passes
   against the live cluster.
2. Per-cohort goldens are stable across two consecutive runs.

### Remaining Work

- Drive every cohort live.
- Commit per-cohort goldens.
- Add the per-seed final-reward distribution assertion.

## Sprint 13.7: Live MinIO Checkpoint Round-Trip and Retention 🔄

**Status**: Active
**Blocked by**: Sprint `13.2`
**Implementation**: `src/JitML/Checkpoint/Store.hs`,
`src/JitML/App.hs`,
`src/JitML/Service/Handlers/Training.hs`
**Docs to update**: `documents/engineering/checkpoint_format.md`,
`documents/engineering/determinism_contract.md`

### Objective

Validate the typed `writeCheckpointSnapshotWithMinIO` + `applyPointerWrite`
path against the live MinIO cluster: blobs and manifests land under
`jitml-checkpoints/<experiment-hash>/`, latest-pointer CAS honours
`If-Match`, retry harness backs off per `RetryPolicy`. The
`jitml internal gc` reconciler runs against the live store, deletes
unreferenced blobs, emits `gc_reaped` Pulsar events, and exits `3` on
steady state.

### Deliverables

- A live checkpoint round-trip test in `jitml-integration` writes a
  manifest + blobs through `writeCheckpointSnapshotWithMinIO`, advances
  the latest pointer, then asserts that a subsequent identical write
  surfaces `SEConflict` for the blob and that the latest-pointer CAS
  honours `If-Match`.
- `jitml internal gc <experiment-hash>` against the live store traverses
  the pointer live set, applies `LastN` retention, reaps unreferenced
  blobs from MinIO via `HasMinIO.deleteObject`, publishes `gc_reaped`
  Pulsar events for each delete, and exits `3` on a steady-state run.

### Validation

1. `jitml-integration --test-options='-p Live'` covers the live
   checkpoint round-trip + CAS retry against the running cluster.
2. `jitml internal gc <experiment-hash>` on a live tree produces
   non-zero reap events on the first run and exits `3` (no-op) on the
   second.

### Remaining Work

- Add the live checkpoint round-trip + CAS retry case in
  `jitml-integration`.
- Wire `gc_reaped` Pulsar event publication into the reconciler.
- Validate against Sprint `13.1`'s cluster.

## Sprint 13.8: Real CUDA RL Algorithm Losses Through JIT Engine 🔄

**Status**: Active
**Blocked by**: Sprint `13.3`
**Implementation**: `src/JitML/RL/Algorithms/{Ppo,A2c,Trpo,MaskablePpo,RecurrentPpo,Dqn,QrDqn,Ddpg,Td3,Sac,CrossQ,Tqc,Ars,Her}.hs`,
`src/JitML/Engines/CudaLocal.hs`,
`src/JitML/Engines/CublasBindings.hs`,
`src/JitML/Engines/CudnnBindings.hs`
**Docs to update**: `documents/engineering/training_workloads.md`,
`documents/engineering/determinism_contract.md`

### Objective

Replace the deterministic-fixture rollout body in each of the 14 RL
algorithm modules with real clipped-surrogate-loss / GAE / KL-trigger /
Bellman-residual / target-network update / quantile TD / hindsight
relabel / evolution-strategy update code, executed through the live
CUDA JIT engine validated by Sprint `7.4`. Adopts `Determinism Contract`
from [../README.md](../README.md).

### Deliverables

- Each on-policy module computes the clipped surrogate loss + GAE
  advantage + KL early-stop against real CUDA-compiled network
  forward/backward kernels.
- Each off-policy module computes the Bellman residual + target-network
  update against real CUDA kernels.
- Each specialised module implements its variant (multi-critic
  averaging, quantile TD, evolution-strategy update, hindsight relabel).
- Per-algorithm + per-environment golden trajectories under
  `test/golden/rl/<algo>/<env>/trajectory.txt` reflect the real
  algorithm output (replace the deterministic-shim goldens committed
  through the Phase `9` code-only sprints).
- The cuDNN deterministic algorithm pin from
  `Engines.Tuning.cuDnnDeterministicAlgorithms` is honoured by the
  off-policy network forward path.

### Validation

1. `cabal test -fcuda jitml-rl-canonicals` on Linux+NVIDIA exits `0`
   with all per-algorithm goldens.
2. Reward thresholds for each algorithm × env cohort match committed
   fixtures within ULP tolerance.

### Remaining Work

- Replace each algorithm module's rollout body with the real update
  code.
- Regenerate per-cohort goldens against the real CUDA engine.
- Validate cuDNN deterministic algorithm pin holds across runs.

## Sprint 13.9: AlphaZero with Real Network Priors 🔄

**Status**: Active
**Blocked by**: Sprint `13.8`
**Implementation**: `src/JitML/RL/AlphaZero/Mcts.hs`,
`src/JitML/RL/AlphaZero/SelfPlay.hs`,
`src/JitML/RL/AlphaZero/Arena.hs`
**Docs to update**: `documents/engineering/training_workloads.md`,
`documents/engineering/determinism_contract.md`

### Objective

Wire `runSearch`'s prior into a real network forward pass through the
JIT engine, run `selfPlayGamesPerGeneration` games per generation with
live MinIO checkpoint round-trip of the self-play buffer, and exercise
the arena promotion path with the real network's win rate. Closes the
`priorFor` legacy ledger row (Sprint 9.5 cleanup).

### Deliverables

- `runSearch` reads its prior from a JIT-compiled policy/value network
  evaluation through `JitML.Engines.HasEngine` instead of the
  deterministic `priorFor` stub.
- `SelfPlayBuffer` round-trips through live MinIO via
  `JitML.Service.MinIOSubprocess`.
- Arena games against a previous-best champion produce real
  `ArenaSummary` counts and promotion decisions.
- `az_games` and `az_sims` report-card knobs from `cabal.project` drive
  the live canonical stanza body.
- The deterministic MCTS prior stub row in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
  moves from `Pending Removal` to `Completed`.

### Validation

1. End-to-end live: one AlphaZero generation runs against a real
   Connect 4 cohort, the buffer round-trips through MinIO, and the
   arena promotion decision matches the committed expected outcome.
2. The deterministic stub is removed from `priorFor` (or the stub is
   replaced by a typed network call).

### Remaining Work

- Implement the network-backed prior.
- Validate the SelfPlayBuffer MinIO round-trip live.
- Wire the report-card knobs.
- Retire the legacy stub row once the network call replaces it.

## Sprint 13.10: Live Tuning Sweep with MinIO Trial Persistence 🔄

**Status**: Active
**Blocked by**: Sprint `13.3`
**Implementation**: `src/JitML/Tune/Catalog.hs`, `src/JitML/Tune/Resume.hs`,
`src/JitML/Service/Handlers/Tune.hs`,
`test/hyperparameter/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Run a full hyperparameter sweep through the live tuner: `jitml tune`
publishes `StartSweep`, the daemon's `TuneHandler` consumes it, trials
execute through the live SL/RL training path, transcripts persist to
MinIO bucket `jitml-trials/<sha256(resolved-dhall || trial-seed)>/`,
and `replaySweep` against the live store reproduces the same trial
outcome bit-for-bit.

### Deliverables

- A full canonical sampler × scheduler × pruner sweep executes through
  the live cluster.
- Trial transcripts persist to MinIO under the canonical bucket prefix.
- `persistTrialTranscript` and `replaySweep` round-trip against live
  HTTP MinIO.
- `tune_trials` / `tune_budget_per_trial` knob consumption extends from
  the local TPE assertion to the full canonical grid.
- Resume-from-partial-sweep equality test reproduces the same outcome.

### Validation

1. `cabal test jitml-hyperparameter --test-options='-p Live'` exits `0`
   against the live cluster.
2. A deliberate sweep restart from a persisted transcript reproduces
   the same final ranking.

### Remaining Work

- Implement the daemon-side `TuneHandler` against live broker.
- Validate `persistTrialTranscript` / `replaySweep` against live MinIO.
- Extend knob consumption to the full grid.
- Add the resume-equality test.

## Sprint 13.11: CUDA and Linux CPU Production Weight Loading 🔄

**Status**: Active
**Blocked by**: Sprint `13.7`
**Implementation**: `src/JitML/Checkpoint/Store.hs`,
`src/JitML/Engines/CudaLocal.hs`,
`src/JitML/Engines/Local.hs`,
`src/JitML/Engines/Loader.hs`
**Docs to update**: `documents/engineering/checkpoint_format.md`,
`documents/engineering/jit_codegen_architecture.md`

### Objective

Extend `loadInferenceCheckpointWithWeights` beyond the existing local
Linux CPU smoke path so real weight blobs decoded from `.jmw1` load
into both Linux CPU oneDNN primitive kernels and Linux CUDA
`MTLBuffer`-equivalent device memory through cuBLAS/cuDNN. Closes the
Linux halves of Exit Definition item 7 (split-blob checkpoint format
with real production weight loading per substrate).

### Deliverables

- `JitML.Engines.Local.runLinuxCpuWeightedKernel` accepts decoded
  weight tensors as oneDNN primitive inputs and feeds them through the
  generated FFI kernel for real network execution (not the current
  smoke fixture).
- `JitML.Engines.CudaLocal.runCudaWeightedKernel` accepts decoded
  weight tensors, allocates device buffers, copies host weights to the
  device, launches the kernel, and copies host output back.
- The daemon's
  `JitML.Service.Runtime.daemonWorkloadDispatcherWithInference`
  dispatches `linux-cpu` and `linux-cuda` + `SelfInference` through the
  weighted runners.

### Validation

1. On Linux+NVIDIA: a canonical inference request through the live
   cluster service pod with `substrate=linux-cuda` produces a
   deterministic output bit-identical to the same request run twice in
   sequence.
2. Same assertion for `substrate=linux-cpu` against the live cluster
   path.

### Remaining Work

- Implement the weighted runners for Linux CPU and CUDA.
- Wire the daemon dispatch.
- Validate live on Linux+NVIDIA.

## Sprint 13.12: Live `jitml inference run` and `jitml inspect replay` 🔄

**Status**: Active
**Blocked by**: Sprint `13.11`
**Implementation**: `src/JitML/App.hs`,
`src/JitML/Checkpoint/Store.hs`,
`src/JitML/Service/MinIOSubprocess.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`,
`documents/engineering/checkpoint_format.md`

### Objective

Extend the user-facing inference and replay commands from the current
local-store path to the live MinIO + JIT cache path: `jitml inference
run` reads the latest pointer from MinIO bucket
`jitml-checkpoints/<experiment-hash>/`, fetches the addressed manifest,
loads weight-only blobs, loads the substrate-bound `KernelHandle` from
the JIT cache, and runs real inference. `jitml inspect replay
<manifest-sha>` fetches the named manifest from live MinIO.

### Deliverables

- `jitml inference run experiments/mnist.dhall --checkpoint latest`
  reads through live MinIO and produces an inference result through
  the loaded JIT kernel.
- `jitml inspect replay <manifest-sha>` reads the named manifest from
  live MinIO and prints the replay summary.
- The Sprint `13.11` weighted runners execute the actual inference; the
  command exits non-zero with `AppError` on missing pointers or
  manifest SHA mismatches.

### Validation

1. End-to-end: `jitml inference run experiments/mnist.dhall --checkpoint
   latest` against the live cluster outputs the expected deterministic
   inference summary.
2. `jitml inspect replay <manifest-sha>` against a manifest written by
   Sprint `13.4` succeeds.

### Remaining Work

- Wire `jitml inference run` user-facing command to the live MinIO +
  JIT-cache + weighted-runner path.
- Wire `jitml inspect replay` to live MinIO manifest read.

## Sprint 13.13: Live `/api/ws` WebSocket Proxy and Compiled Halogen Bundle 🔄

**Status**: Active
**Blocked by**: Sprint `13.3`
**Implementation**: `src/JitML/Web/Server.hs`,
`web/src/Panels/{Mnist,Cifar,Connect4,Rl,Training,Tune}.purs`,
`web/spago.yaml`, `docker/Dockerfile`
**Docs to update**: `documents/engineering/purescript_frontend.md`,
`documents/engineering/daemon_architecture.md`

### Objective

Replace the deterministic local stream frames served from `/api/ws*`
with a live WebSocket proxy that bridges browser clients to the
daemon's metric/event Pulsar topics. The compiled Halogen bundle
(baked into `jitml:local` per Sprint `11.5`) renders against live
daemon state. Closes Exit Definition item 8's live-panel slice.

### Deliverables

- `JitML.Web.Server` accepts `/api/ws`, `/api/ws/training`, and
  `/api/ws/tune` upgrade requests, opens a Pulsar WebSocket subscription
  to the matching event topic, and forwards frames downstream.
- The six Halogen panels (`Panels.{Mnist,Cifar,Connect4,Rl,Training,Tune}`)
  render against live frames received through the proxy.
- The demo `web/dist/Main/index.js` baked into `jitml:local` renders
  against the live `/api/ws` proxy when served from the cluster
  `jitml-demo` pod.

### Validation

1. Manual: the demo loaded in a browser against the live Envoy edge
   route shows real-time updates while a live training/tune run is in
   progress.
2. `JitML.Web.Server` proxy correctness is exercised by an automated
   test that publishes a known event on the broker and asserts the
   browser client receives a matching frame.

### Remaining Work

- Implement the live WebSocket proxy.
- Add Halogen render machinery (slot + state + DOM diff) to each
  `Panels.*` module.
- Validate the live render against the cluster.

## Sprint 13.14: Live Playwright on Demo Edge Route 🔄

**Status**: Active
**Blocked by**: Sprint `13.13`
**Implementation**: `playwright/jitml-demo.spec.ts`,
`infra/pulumi/index.ts`,
`src/JitML/Test/LivePlan.hs`
**Docs to update**: `documents/engineering/purescript_frontend.md`,
`documents/engineering/unit_testing_policy.md`

### Objective

Execute the seven-test Playwright canonical panel matrix
(`mnist-live-inference`, `cifar-imagenet-upload`,
`connect4-human-vs-alphazero`, `rl-trajectory`, `training-progress`,
`hyperparameter-sweep`, smoke shell) against the live `jitml-demo`
served behind the Envoy edge route, replacing the current inline
`page.setContent` DOM stubs. Closes Exit Definition item 8's Playwright
slice and item 9's `jitml-e2e` Playwright slice.

### Deliverables

- `playwright/jitml-demo.spec.ts` reads the leased edge port from
  `cluster-publication.json` and loads
  `http://127.0.0.1:<edge-port>/...` for each panel test instead of
  using `page.setContent`.
- The typed `JitML.Test.LivePlan` sequence drives `helm dependency
  build chart` → `pulumi up` → `npx playwright test` → `pulumi
  destroy` → `pulumi stack rm` on Linux+Docker+NVIDIA.
- Post-teardown the explicit live e2e path leaves no `jitml-e2e-*` Kind
  cluster, no Harbor project, no MinIO bucket, and no Docker volume on
  the host.

### Validation

1. The explicit live `jitml-e2e` orchestration command exits `0`,
   including the Playwright run.
2. Post-teardown grep for leaked resources returns empty.

### Remaining Work

- Wire Playwright against the live edge route.
- Run the full live orchestration on Linux+NVIDIA.
- Validate post-teardown cleanup.

## Sprint 13.15: Linux CPU Full-Tensor Benchmark Payloads and First-Cache-Miss Live Execution 🔄

**Status**: Active
**Blocked by**: Sprint `13.11`
**Implementation**: `src/JitML/Engines/TuningBenchmark.hs`,
`src/JitML/Engines/Loader.hs`,
`src/JitML/Engines/Local.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`

### Objective

Replace the current Linux CPU oneDNN benchmark candidate runner's
single-tensor payload with the full-tensor benchmark payload supplied
by the checkpoint ABI from Sprint `13.11`, and execute the live
first-cache-miss benchmark path on Linux CPU so the persisted
`TuningChoice` reflects real measured selection.

### Deliverables

- `linuxCpuBenchmarkCandidateRunner` consumes full-tensor inputs from
  the loaded checkpoint ABI.
- The first cache-miss for a Linux CPU kernel on the live cluster
  drives the benchmark runner; the persisted selection lands under
  `./.build/jit/tuning/linux-cpu/<base-hash>.json`.
- A subsequent build of the same kernel reads the persisted choice.

### Validation

1. On Linux: a controlled first cache miss for a `linux-cpu` kernel
   with a non-trivial tensor payload selects a tuning choice live and
   persists it; the second build hits the persisted choice.

### Remaining Work

- Extend `linuxCpuBenchmarkCandidateRunner` to full tensors.
- Validate the live first-cache-miss path on Linux.

## Doctrine Sections Cited

- [../README.md → Reconcilers: Idempotent Mutation as a Single Command](../README.md#doctrine-scope) (Sprint 13.1 — live `pulumi up` + Helm rollout, Sprint 13.7 — live `jitml internal gc`)
- [../README.md → Capability Classes and Service Errors](../README.md#doctrine-scope) (Sprints 13.2, 13.7, 13.10, 13.11, 13.12 — live `HasMinIO` / `HasPulsar` / `HasHarbor`)
- [../README.md → At-Least-Once Event Processing](../README.md#doctrine-scope) (Sprints 13.3, 13.4, 13.6, 13.10 — live broker consumer with dedup)
- [../README.md → Retry Policy as First-Class Values](../README.md#doctrine-scope) (Sprints 13.3, 13.7 — `RetryPolicy` over live broker / MinIO)
- [../README.md → Plan / Apply commands](../README.md#doctrine-scope) (Sprints 13.4, 13.6, 13.10, 13.12 — live `jitml train` / `jitml rl train` / `jitml tune` / `jitml inference run`)
- [../README.md → Determinism Contract](../README.md#doctrine-scope) (Sprints 13.8, 13.9, 13.11 — cuDNN deterministic pin + cross-substrate ULP tolerance)
- [../README.md → Test-suite stanzas](../README.md#test-suite-stanzas) (Sprints 13.1, 13.14 — live `jitml-e2e`)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/cluster_topology.md` — record live Pulumi /
  Kind / Helm orchestration once Sprint `13.1` closes.
- `documents/engineering/daemon_architecture.md` — record live broker
  consumer handlers once Sprint `13.3` closes; live `/api/ws` proxy
  once Sprint `13.13` closes.
- `documents/engineering/checkpoint_format.md` — record live MinIO
  conditional-write + GC + production weight loading once Sprints
  `13.7` and `13.11` close.
- `documents/engineering/training_workloads.md` — record live SL / RL /
  AlphaZero / tune E2E once Sprints `13.4`, `13.6`, `13.8`, `13.9`, and
  `13.10` close.
- `documents/engineering/jit_codegen_architecture.md` — record live
  benchmark candidate selection on Linux CPU + CUDA once Sprint `13.15`
  closes.
- `documents/engineering/purescript_frontend.md` — record live Halogen
  bundle + WebSocket proxy + Playwright closure once Sprints `13.13`
  and `13.14` close.
- `documents/engineering/determinism_contract.md` — record real CUDA
  bit-equality once Sprint `13.8` closes; cross-substrate ULP work
  lives in Phase `15`.
- `documents/engineering/unit_testing_policy.md` — note live `jitml-e2e`
  closure once Sprint `13.14` closes.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → Substrates` row for `linux-cuda` flips from
  Active to Done once Sprint `13.11` closes.
- `system-components.md → Stateful Platform Services` rows flip from
  partial to Done once Sprint `13.2` closes.
- `system-components.md → Test Stanzas` row for `jitml-e2e` flips to
  Done once Sprint `13.14` closes.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [phase-7-jit-codegen-and-substrates.md](phase-7-jit-codegen-and-substrates.md)
- [phase-8-supervised-and-rl-framework.md](phase-8-supervised-and-rl-framework.md)
- [phase-9-rl-catalog-alphazero-and-tuning.md](phase-9-rl-catalog-alphazero-and-tuning.md)
- [phase-10-checkpointing-and-inference.md](phase-10-checkpointing-and-inference.md)
- [phase-11-purescript-frontend-and-demo.md](phase-11-purescript-frontend-and-demo.md)
- [phase-12-test-stanzas-and-cross-cluster.md](phase-12-test-stanzas-and-cross-cluster.md)
- [phase-14-apple-silicon-closure.md](phase-14-apple-silicon-closure.md)
- [phase-15-cross-substrate-and-handoff.md](phase-15-cross-substrate-and-handoff.md)
- [../README.md](../README.md)

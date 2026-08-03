# Phase 172: Real RL Environment Simulators and Daemon Env Loop

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Real RL Environment Simulators and Daemon Env Loop. Single-session phase migrated from legacy Sprint 15.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 172.1: Real RL Environment Simulators and Daemon Env Loop [✅ Done]

**Status**: Done (re-validated 2026-06-06 on RTX 5090; previously Done on RTX 3090) (closed 2026-05-28)
**Blocked by**: Sprint `170.1`
**Implementation**: `src/JitML/RL/Environments.hs`,
`src/JitML/RL/Loop.hs`,
`src/JitML/RL/Simulator.hs`,
`src/JitML/RL/SimulatorLoop.hs`,
`src/JitML/App.hs`,
`src/JitML/Service/Workload.hs`, `src/JitML/Service/Runtime.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Run the daemon-backed environment loop against the pure-Haskell
simulators in `JitML.RL.Simulator` (Phase 8 Sprint 8.3 closure
chose pure-Haskell ports over Box2D/ALE FFI per the
[determinism contract](../documents/engineering/determinism_contract.md);
real cross-version float drift in third-party physics libraries
disfavours the FFI route). Expose the typed env-step boundary and
drive `runSimulatedEpisodes` from the worker-side `jitml rl train`
under the daemon's dispatch chain.

### Deliverables

- Real simulator bindings for `cartpole`, `mountain-car`, `lunar-lander`, and
  the then-current `atari-subset` stand-in in `JitML.RL.Simulator` —
  pure-Haskell ports following the Gym reference equations rather than
  Box2D/ALE FFI per the determinism contract. Phase `8` Sprint `8.8`
  superseded the `atari-subset` stand-in with optional ALE support, and Sprint
  `8.9` now owns the copyright-free `KeyDoorGrid-v0` default demo replacement.
- `step :: Env -> Action -> IO (Obs, Reward, Done)` exposed through the
  typed boundary, including render-frame access for the demo.
- The daemon-backed environment loop drives the simulator-loop
  through the worker `jitml rl train` under
  `daemonWorkloadDispatcher`. That historical episode envelope was superseded:
  the current Phase `252` worker publishes plan-bound keyed
  `RlEvaluation (EvaluationOutcome)` evidence separately from ordered
  `RlIteration (IterationSummary)` learning telemetry.

### Validation

1. On Linux: `cabal test jitml-rl-canonicals` exercises the
   simulator-loop run-to-run determinism assertion (Sprint 15.6
   shared closure) for every entry in
   `SimulatorLoop.simulatedEnvCatalog`.
2. End-to-end: a live `jitml rl train experiments/cartpole.dhall`
   reaches the canonical reward threshold against the real cartpole
   simulator inside the cluster daemon.

### Code Surface Landed (2026-05-27, simulator loop wiring)

This subsection records the historical landing. `SimulatorLoop` and the
`publishWorkerRlEpisode` envelope were later removed; real per-algorithm
trainers now return measured counters, ordered learning curves, and exact
evaluation sets through `JitML.RL.TrainerExecution`.

- `src/JitML/RL/SimulatorLoop.hs` adds an existential
  `SimulatedEnvByName` wrapper around the four simulator entries that were
  current at landing time (cartpole / mountain-car / lunar-lander /
  atari-subset) plus the
  deterministic `runSimulatedEpisode` / `runSimulatedEpisodes` driver
  using the same `(stepIx + episodeId + seed) `mod` actionCount`
  policy the existing `JitML.RL.Loop.runRLLoop` used. The real
  per-environment physics already lived in `JitML.RL.Simulator`
  (Phase 8 Sprint 8.3 pure-Haskell ports); this module adds the
  episode driver around it.
- `JitML.App.runRl ["rl", "train"]` now reads `JITML_ENVIRONMENT`,
  `JITML_SEED`, `JITML_MAX_STEPS`, `JITML_EVAL_EPISODES` from the
  daemon-rendered Job env (Sprint 15.3 `renderRlJob`), looks up the
  matching simulator through `SimulatorLoop.lookupSimulatedEnvByName`,
  runs `runSimulatedEpisodesByName`, prints the per-episode summary,
  and calls `publishWorkerRlEpisode` per episode. The legacy
  single-event `publishWorkerRlEvent` is replaced by
  `publishWorkerRlEpisode :: SimulatedEpisode -> App ()` so every
  episode generates one envelope on `rl.event.<substrate>`.
- New env-var helpers `envWithDefault` and `readIntDefault` in
  `JitML.App` so the same parsing applies to other `JITML_*` env vars
  in subsequent sprints.

### Code Surface Landed (2026-05-27, fifth session — PPO trainer dispatch)

- `JitML.App.runRl` now reads `JITML_RL_TRAINER` (default
  `"simulator"`). When set to `"ppo"` on the cartpole env it drives
  the real `JitML.RL.Algorithms.PpoTrainer.trainPpoOnCartpole` loop
  through `runPpoTrainerEpisodes`, projecting the per-iteration mean
  reward into the existing `SimulatedEpisode` envelope shape so the
  worker → broker publication path (`publishWorkerRlEpisode`) is
  unchanged. Other trainers keep the deterministic simulator loop.
- `JitML.Service.Workload.renderRlJob` now sets `JITML_RL_TRAINER`
  from the algorithm name via `rlTrainerForAlgorithm` — `PPO` maps to
  `"ppo"`, everything else to `"simulator"` — so a daemon-dispatched
  `StartRLRun` for PPO runs the real trainer inside the Kubernetes Job.

### Live Validation Note (2026-05-27, fifth session)

On the RTX 3090 / CUDA 12.8 cluster, `jitml rl train
experiments/cartpole.dhall` with `JITML_RL_TRAINER=ppo
JITML_ENVIRONMENT=cartpole JITML_EVAL_EPISODES=40
JITML_MAX_STEPS=2048` ran the real MLP-backed PPO loop through the
production `jitml:local` binary and reported `episodes: 40 /
avg-reward: 472.6` (the converged policy reaches the 500-step
`cartpole_v1` cap; the per-iteration median clears the literature
target of 475 from iteration ~16). The daemon holds the
`rl.command.linux-cuda` subscription as `jitml-service` (confirmed
via `kubectl logs deploy/jitml-service`).

### Live Validation Note (2026-05-28 — daemon-dispatched RL episode arrival)

Closes Sprint 15.5's last obligation. To make the worker publish events
back from inside a Job pod (which cannot reach the host edge
`127.0.0.1:<edge-port>`), the daemon-rendered Job now sets
`JITML_PULSAR_WS` (the in-cluster broker WebSocket endpoint
`ws://pulsar-broker.platform.svc.cluster.local:8080/ws`) in
`renderRlJob` / `renderTrainingJob` / `renderTuneJob`, and
`JitML.App.workerBrokerTarget` resolves the worker's publish settings
from `JITML_PULSAR_WS` + `JITML_SUBSTRATE` (falling back to the host-edge
publication for offline runs). New `jitml-integration` Live case `live
daemon dispatches StartRLRun into a Job and per-episode events arrive on
rl.event (Sprint 15.5/15.6)` publishes a `StartRLRun` on
`rl.command.linux-cuda`, waits for the dispatched `jitml-rl-<hash>` Job,
and consumes the per-episode `EpisodeDone` envelopes off
`rl.event.linux-cuda`, asserting they arrive in non-decreasing episode
order. Validated against the live RTX 3090 / CUDA 12.8 cluster (rebuilt
`jitml:local` image with the worker→broker wiring):

```
live daemon dispatches StartRLRun into a Job and per-episode events arrive on rl.event (Sprint 15.5/15.6): OK (1.77s)
```

Full Live cohort: 16 / 16 pass.

### Remaining Work

- None remaining for Sprint 13.5. Sprint closed 2026-05-28.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

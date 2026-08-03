# Phase 170: Daemon Training/RL/Tune Handlers on Live Broker

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Daemon Training/RL/Tune Handlers on Live Broker. Single-session phase migrated from legacy Sprint 15.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 170.1: Daemon Training/RL/Tune Handlers on Live Broker [✅ Done]

**Status**: Done (re-validated 2026-06-06 on RTX 5090; previously Done on RTX 3090) (closed 2026-05-29 — the reopened scope for typed Dhall
`RunConfig` dispatch was live-validated end-to-end. See the **Live re-verification
(2026-05-29, post `workerExperimentHash` fix)** block below.)
**Blocked by**: Sprint `169.1`
**Implementation**: `src/JitML/Service/Runtime.hs`,
`src/JitML/Service/Consumer.hs`,
`src/JitML/Service/Workload.hs`, `test/integration/Main.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`,
`documents/engineering/training_workloads.md`

**Note on the planned `Handlers/Training.hs`, `Handlers/Rl.hs`,
`Handlers/Tune.hs` modules**: the daemon's per-domain dispatch already
lives in `JitML.Service.Workload.trainingCommandEffects` /
`tuneCommandEffects` / `rlCommandEffects` and is invoked through
`daemonWorkloadDispatcher`. Splitting these into separate `Handlers/*`
modules would be pure code shuffling with no behaviour change. The plan
will not ship that split unless a future cohort introduces per-handler
state that warrants it; see Remaining Work for the doctrine deviation
note.

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

### Code Surface Landed (2026-05-25)

- A new `Live` test case `live daemon dispatches StartTraining into a
  Kubernetes Job (Sprint 15.3)` in `test/integration/Main.hs` publishes
  a `StartTraining` envelope on the substrate-scoped command topic
  through the routed Pulsar WebSocket subprocess, waits up to 15
  seconds for the daemon to consume + dispatch, then asserts via
  `kubectl get job jitml-train-<hash> -n platform` that the
  expected workload Job exists. The test cleans up the Job on success.
- Helpers (`waitForJob`, `kubectlJobExists`, `deleteJob`) are added to
  `test/integration/Main.hs` and call `kubectl` through the typed
  `runStreaming` boundary against the repo-local
  `./.build/jitml.kubeconfig`.

### Code Surface Landed (2026-05-27, dedup live assertion)

- New `Live` case `live duplicate StartTraining produces one daemon-
  side dedup-skip (Sprint 15.3 dedup)` in `test/integration/Main.hs`:
  (a) snapshots the cluster daemon log byte length via
  `kubectl logs deploy/jitml-service`, (b) publishes the *identical*
  `StartTraining` payload twice on `training.command.<substrate>`
  through the same Pulsar WebSocket subprocess the daemon consumes
  from, (c) waits for the dispatched Kubernetes Job to appear (proof
  the first consume reached the dispatcher), (d) tails the daemon
  log since the snapshot and asserts at least one
  `deduplicated training <event-id>` line appears matching the
  SHA-256 of the published payload — evidence that
  `HandlerRouter.routeByKindAt` skipped dispatch on the second
  consume. The eventId is derived locally via
  the then-current `JitML.Service.Consumer.eventIdFromPayload` so the assertion
  did not depend on any other test infrastructure. Sprint `8.16` supersedes
  this dated validation helper with plan/kind/key-derived semantic identity.
- New helpers `daemonLogByteSize` and `daemonLogTailSinceBytes` in
  `test/integration/Main.hs` shell out to `kubectl logs
  deploy/jitml-service` through the typed `runStreaming` boundary
  and slice the result by byte length so the dedup test sees only
  lines emitted during its window.
- `EventId (..)` is now imported from `JitML.Service.Consumer` so the
  test code can render the eventId directly into the daemon log
  needle.

### Live Validation Note (2026-05-25)

Validation host: same Linux+NVIDIA host as Sprints 15.1 / 13.2. Driver:
`docker compose run --rm jitml cabal test --builddir=/root/dist-jitml
jitml-integration --test-options='-p Live'` against the Sprint 15.1
cluster at `127.0.0.1:9092`.

```
jitml-integration
  Live
    live HasMinIO conditional writes round-trip on jitml-checkpoints:         OK (0.10s)
    live HasMinIO listObjects sees a freshly written object:                  OK (0.04s)
    live HasPulsar publish/subscribe/consume round-trip on training.command:  OK (0.36s)
    live daemon dispatches StartTraining into a Kubernetes Job (Sprint 15.3): OK (1.22s)

All 51 tests passed (1.92s)
Test suite jitml-integration: PASS
```

The daemon log surfaced from `kubectl logs deploy/jitml-service`
confirms the four expected subscriptions are held by the cluster
daemon as `jitml-service`:

```
pulsar_subscriptions:
  - persistent://public/default/training.command.linux-cuda as jitml-service
  - persistent://public/default/tune.command.linux-cuda as jitml-service
  - persistent://public/default/rl.command.linux-cuda as jitml-service
  - persistent://public/default/inference.request.linux-cuda as jitml-service
```

The dispatched `jitml-train-<hash>` Job ran `jitml train
experiments/mnist.dhall` and exited `Complete` (durations ~4s). The Job
stdout shows the deterministic local SL summary
(`final_loss: 0.7496644`); the Job does **not** yet publish a Pulsar
`EpochCompleted` event back through the broker. Closing that loop is
Sprint `15.4`'s responsibility — the daemon's dispatch path is
validated here, the worker-side event publication is the next phase.

### Code Surface Landed (2026-05-26, worker-side event publication)

- `JitML.App.publishWorkerTrainingEvent` publishes one
  `TrainingEpoch (EpochCompleted ...)` envelope to
  `training.event.<substrate>` after the worker `jitml train`
  command's deterministic summary, when the worker is running in
  cluster context (live publication present + `JITML_EXPERIMENT_HASH`
  exported by the daemon-rendered Job env).
- At this historical landing, `JitML.App.publishWorkerRlEvent` published one
  episode envelope to `rl.event.<substrate>` after `jitml rl train`. The
  current Phase `252` surface instead publishes plan-bound keyed
  `RlEvaluation (EvaluationOutcome)` evidence separately from ordered
  `RlIteration (IterationSummary)` learning telemetry.
- `JitML.App.publishWorkerTuneEvent` iterates the configured trial
  budget (from `JITML_TRIAL_BUDGET` / `JITML_SWEEP_SEED` env vars),
  persists a `TrialTranscript` to MinIO per seed via
  `JitML.Tune.Resume.persistTrialTranscript`, publishes
  `TuneTrialStarted` + `TuneTrialFinished` envelopes per trial, then
  publishes a final `TuneSweepDone` envelope.
- Publication failures are logged to stderr but do not roll back the
  worker exit — at-least-once handles the missed event on the next
  daemon dispatch (consistent with the
  [README.md → At-Least-Once Event Processing](../README.md) discipline).

### Live Validation Note (2026-05-27, dedup pass)

`cabal test jitml-integration --test-options='-p Live'` against a
fresh `jitml bootstrap --linux-cuda` cluster (RTX 3090 / CUDA 12.8 /
Ubuntu 24.04 host) — 14 / 14 Live cases pass in 14.88s, including
the new dedup assertion:

```
live duplicate StartTraining produces one daemon-side dedup-skip (Sprint 15.3 dedup): OK (0.34s)
```

The dedup assertion required a daemon-stdout line-buffering fix in
`JitML.App.runService` (`hSetBuffering stdout LineBuffering`) so that
Kubernetes pipe-based log capture flushes the per-delivery
`service: deduplicated training <event-id>` lines as they land
rather than batching them into 4 KB blocks. Without that fix the
daemon's actual dedup behaviour stayed invisible to `kubectl logs
deploy/jitml-service`.

### Remaining Work

- None remaining for Sprint 13.3. Sprint closed 2026-05-29.

### Live re-verification (2026-05-29, post `workerExperimentHash` fix)

Validation host: same Linux+NVIDIA host as the rest of Phase `15`. Driver:
`docker compose run --rm jitml cabal test --builddir=/root/dist-jitml
jitml-integration --test-options='-p Live'` against the bootstrapped
`linux-cuda` cluster (Sprint 15.1 closure, kind node cap 10 GiB / 6 CPUs).

The reopened scope — daemon dispatch through typed Dhall `RunConfig` +
`BootConfig` mounts with the `JITML_*` run-parameter env IPC removed — was
live-validated end-to-end:

- **Worker-side experimentHash now flows from typed Dhall.** A new
  `JitML.App.workerExperimentHash` helper tries each `RunConfig` variant in
  turn (`tryLoadRlRunConfig` → `tryLoadTrainingRunConfig` →
  `tryLoadTuneRunConfig` against `/etc/jitml/run/RunConfig.dhall`) before
  falling back to the legacy `JITML_EXPERIMENT_HASH` env. The three worker
  publishers used this helper, closing the last gap that Sprint `5.7` left
  behind for cluster-dispatched runs. The RL publisher names and envelope shape
  were later replaced by Phase `252`'s separate iteration/evaluation events.
- **Test pass.** All 17 Live cases passed in `18.36s` (vs. the prior 152.57s
  RL failure that surfaced this gap):
  ```
  jitml-integration / Live
    live HasMinIO conditional writes round-trip on jitml-checkpoints                                                                  OK (0.12s)
    live HasMinIO listObjects sees a freshly written object                                                                           OK (0.04s)
    live HasPulsar publish/subscribe/consume round-trip on training.command                                                           OK (0.44s)
    live jitml-service holds subscriptions on all four daemon command topics (Sprint 15.2 acquisition)                                OK (8.23s)
    live HasHarbor same-repository tag promotion round-trip (Sprint 15.2 Harbor)                                                      OK (1.79s)
    live daemon dispatches StartTraining into a Kubernetes Job (Sprint 15.3)                                                          OK (1.22s)
    live duplicate StartTraining produces one daemon-side dedup-skip (Sprint 15.3 dedup)                                              OK (0.35s)
    live daemon dispatches StartRLRun into a Job and per-episode events arrive on rl.event (Sprint 15.5/15.6)                         OK (1.73s)
    live checkpoint snapshot round-trip through MinIOSubprocess (Sprint 15.7)                                                         OK (0.14s)
    live GC: listCheckpointManifestsMinIO + executeGcPlan reap (Sprint 15.7)                                                          OK (0.25s)
    live jitml internal gc reaps from live MinIO (Sprint 15.7 CLI)                                                                    OK (1.24s)
    live jitml internal gc publishes GcReapedEvent on gc.event.<substrate> (Sprint 15.7 events)                                       OK (0.69s)
    live jitml inference run reads checkpoint from live MinIO (Sprint 15.12)                                                          OK (0.71s)
    live tune trial persist + replay round-trip (Sprint 15.10)                                                                        OK (0.11s)
    live daemon TuneHandler dispatches StartSweep into a Kubernetes Job (Sprint 15.10 daemon)                                         OK (1.24s)
    live SelfPlayBuffer MinIO round-trip via writeSelfPlayBuffer / readSelfPlayBuffer (Sprint 15.9)                                   OK (0.04s)
    live AlphaZero generation drive: self-play + training, then .jmw1 weight checkpoint round-trips through live MinIO (Sprint 15.9)  OK (0.04s)
  All 17 tests passed (18.36s)
  ```
- The dispatched training/RL/tune Jobs carry zero `JITML_*` run-parameter env
  on their pod specs (the daemon mounts `RunConfig.dhall` via a per-run
  ConfigMap at `/etc/jitml/run/` and the shared `jitml-service-config` mount
  at `/etc/jitml/service/`). The worker observably published `EpisodeDone`
  envelopes on `rl.event.linux-cuda` keyed by the experiment hash carried in
  the mounted `RunConfig` — exactly the live-event arrival the Sprint
  `15.5`/`15.6` assertion required.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

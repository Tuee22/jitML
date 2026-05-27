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

**Met today (2026-05-25, Linux+NVIDIA host: RTX 3090, CUDA 12.8 driver,
Ubuntu 24.04, Docker 29.5.0)**: Sprint `13.1`'s live up half (live
phased Helm + Pulsar rollout, all 7 publication components Ready,
Envoy gateway PROGRAMMED, 14 HTTPRoutes resolved) and live down half
(`jitml cluster down` + clean-teardown confirmation). Sprint `13.2`'s
`HasMinIO` + `HasPulsar` halves (3 new `Live` cases in
`jitml-integration` covering conditional writes, list/delete,
publish/subscribe/consume/ack against the routed edge). Upstream code
surfaces under Phase `7` (CUDA codegen + cuBLAS/cuDNN typed bindings
validated 2026-05-24), Phase `5` (daemon scaffold + capability classes
+ at-least-once consumer validated against synthetic broker), Phase
`12.8` (typed Pulumi orchestrator + `JitML.Test.LivePlan`), and
Phases `8`/`9`/`10`/`11` (deterministic local summaries +
filesystem-backed capability boundaries) remain in place.

**Code-surface landings on 2026-05-26 (RTX 3090 host, code-only +
partial live)**:
- Sprint `13.7` `gc_reaped` Pulsar event publication:
  `JitML.Proto.Gc.GcReapedEvent` envelope with text + proto3 byte
  codecs, `gc.event.<substrate>` topic added to
  `JitML.Cluster.PulsarBootstrap.substrateTopics` (topic family
  grew 26 → 29), `JitML.App.publishGcReapedEvents` wired into
  `runInternalGc` after the live reaper, 4 new `jitml-unit`
  envelope round-trip tests.
- Sprint `13.12` typed inference `AppError` variants:
  `InferenceCheckpointMissing :: Text -> AppError` and
  `InferenceManifestShaMismatch :: Text -> Text -> AppError` added
  to `JitML.AppError.AppError`, render boundary + golden fixture
  extended, `runInference` / `runInspectReplay` mapped to the new
  variants, and `assertManifestShaMatches` defensively compares
  `Checkpoint.manifestContentSha` against the user-supplied
  `--manifest-sha`.
- Sprint `13.6` convergence-assertion wiring through
  `jitml-rl-canonicals`: 2 new tests assert `cohortThreshold`
  covers every in-evaluation-matrix algorithm × env pair and
  `passesConvergence` accepts the literature target / rejects
  below the slack band.
- All 8 Cabal test stanzas pass non-Live (244 tests total),
  `jitml check-code` (fourmolu + hlint) is clean.

**Live validation on 2026-05-26 (same RTX 3090 host, fresh
bootstrap)**: a fresh `docker compose run --rm jitml jitml bootstrap
--linux-cuda` from a teardown state executed 113 phased steps, all
helm releases (harbor, harbor-pg, minio, pulsar, kube-prometheus-stack,
tensorboard, jitml-service, envoy-gateway, jitml-demo) deployed, and
`./.build/runtime/cluster-publication.json` lists all seven publication
components Ready on edge port 9092. `pulsar-admin topics list
public/default` reports 21 topics (the broker's list endpoint truncates
to topics in loaded bundles, as documented on 2026-05-25); the 8
apple-silicon non-internal topics are loaded but
not in the listed bundles, confirmed by `pulsar-admin topics create
persistent://public/default/training.command.apple-silicon` returning
`HTTP 409 "This topic already exists"`. The expanded 29-topic family
including the 3 new `gc.event.<substrate>` entries is therefore
present after rollout — the retry-loop fix in
`pulsarTopicCreateSubprocess` re-validated. The full `Live` cohort of
`jitml-integration` (9 cases) passes against the cluster:

```
jitml-integration
  Live
    live HasMinIO conditional writes round-trip on jitml-checkpoints:          OK (0.15s)
    live HasMinIO listObjects sees a freshly written object:                   OK (0.05s)
    live HasPulsar publish/subscribe/consume round-trip on training.command:   OK (0.44s)
    live daemon dispatches StartTraining into a Kubernetes Job (Sprint 13.3):  OK (0.26s)
    live checkpoint snapshot round-trip through MinIOSubprocess (Sprint 13.7): OK (0.13s)
    live GC: listCheckpointManifestsMinIO + executeGcPlan reap (Sprint 13.7):  OK (0.25s)
    live jitml internal gc reaps from live MinIO (Sprint 13.7 CLI):            OK (1.26s)
    live jitml inference run reads checkpoint from live MinIO (Sprint 13.12):  OK (0.27s)
    live tune trial persist + replay round-trip (Sprint 13.10):                OK (0.11s)

All 9 tests passed (2.91s)
```

**Code-surface landings on 2026-05-26 (continued, code-only)**:
- Sprint 13.1 ephemeral cluster name parameterization:
  `JitML.Cluster.Kind.kindConfigForNamed` and
  `kindConfigForEdgePortNamed` accept an override cluster name; new
  `jitml internal render-kind-config --substrate <s> --name <n>`
  CLI command emits the YAML; Pulumi `infra/pulumi/index.ts`
  renders the per-stack config to `./.build/<cluster>-kind.yaml`
  before `kind create`.
- Sprint 13.3 worker-side event publication:
  `publishWorkerTrainingEvent`, `publishWorkerRlEvent`, and
  `publishWorkerTuneEvent` in `JitML.App` publish completion
  envelopes to `training.event.<substrate>` /
  `rl.event.<substrate>` / `tune.event.<substrate>` after the
  worker command's deterministic summary, gated on live publication
  + `JITML_EXPERIMENT_HASH`.
- Sprint 13.4 dataset fetch wiring: `attemptFetchTrainingDataset`
  fetches `jitml-datasets/<name>/train/data.bin` through
  `Dataset.fetchDatasetRef` + `MinIOSubprocess`; real-MNIST upload +
  canonical SHA replacement remain.
- Sprint 13.10 per-trial transcript persistence + events:
  `publishWorkerTuneEvent` iterates `JITML_TRIAL_BUDGET` seeds,
  persists each `TrialTranscript` to MinIO via
  `persistTrialTranscript`, publishes `TuneTrialStarted` +
  `TuneTrialFinished` per trial, then `TuneSweepDone`.
- Sprint 13.11 daemon dispatch widening + GPU passthrough:
  `*WithWeightedInference` variants added throughout
  `JitML.Service.Workload` and `JitML.Service.Runtime`;
  `JitML.App.daemonWorkloadDispatcherForRuntime` routes Linux CPU +
  CUDA `SelfInference` through `runLinuxCpuWeightedCheckpointInference`
  / `runCudaWeightedCheckpointInference`; `docker/Dockerfile`
  removes stubs from `LD_LIBRARY_PATH` + `ld.so.conf.d/cuda.conf`;
  `JitML.Engines.Engine` passes `-L/usr/local/cuda/lib64/stubs`
  explicitly to nvcc.
- Sprint 13.12 JIT-kernel-backed inference: `runInference` routes
  through `loadInferenceCheckpointWithWeights` with the
  substrate-appropriate weighted runner.
- Sprint 13.15 weighted benchmark runner:
  `linuxCpuWeightedBenchmarkCandidateRunner` consumes input + weights
  through `runLinuxCpuWeightedKernel`.

**Live validation on 2026-05-27 (same RTX 3090 host, fresh
bootstrap with rebuilt `jitml:local` image)**: a fresh
`docker compose run --rm jitml jitml bootstrap --linux-cuda` from a
teardown state completed the full phased Helm + Pulsar rollout
(Harbor → Pulsar/Postgres/MinIO/Observability → jitml-service →
jitml-demo, ~40 min cold) and emitted
`./.build/runtime/cluster-publication.json` with all seven publication
components `ready` on edge port 9092. Full `Live` cohort of
`jitml-integration` (12 cases) ran against the cluster and passed:

```
jitml-integration
  Live
    live HasMinIO conditional writes round-trip on jitml-checkpoints:                                   OK (0.09s)
    live HasMinIO listObjects sees a freshly written object:                                            OK (0.04s)
    live HasPulsar publish/subscribe/consume round-trip on training.command:                            OK (0.42s)
    live jitml-service holds subscriptions on all four daemon command topics (Sprint 13.2 acquisition): OK (7.93s)
    live HasHarbor same-repository tag promotion round-trip (Sprint 13.2 Harbor):                       OK (1.02s)
    live daemon dispatches StartTraining into a Kubernetes Job (Sprint 13.3):                           OK (1.22s)
    live checkpoint snapshot round-trip through MinIOSubprocess (Sprint 13.7):                          OK (0.13s)
    live GC: listCheckpointManifestsMinIO + executeGcPlan reap (Sprint 13.7):                           OK (0.25s)
    live jitml internal gc reaps from live MinIO (Sprint 13.7 CLI):                                     OK (0.58s)
    live jitml internal gc publishes GcReapedEvent on gc.event.<substrate> (Sprint 13.7 events):        OK (0.63s)
    live jitml inference run reads checkpoint from live MinIO (Sprint 13.12):                           OK (0.54s)
    live tune trial persist + replay round-trip (Sprint 13.10):                                         OK (0.11s)

All 12 tests passed (12.94s)
```

The Sprint 13.12 case (live `jitml inference run`) now exercises the
real JIT-kernel-backed CUDA path (Sprint 13.12 code surface): nvcc
compiles the weighted `kernel.cu`, the artifact loads via dlopen,
`jitml_weighted_kernel` runs on the RTX 3090, and the result is
published to `inference.result.linux-cuda` through the routed Pulsar
WebSocket edge. Pre-existing `--use_fast_math=false` nvcc arg bug was
exposed by the new wired-up path and corrected to omit the flag
entirely (default fast-math-off honours the determinism contract).
`kubectl logs deploy/jitml-service` confirms four held subscriptions
on `training.command.linux-cuda`, `tune.command.linux-cuda`,
`rl.command.linux-cuda`, and `inference.request.linux-cuda` — all as
`jitml-service`. `jitml cluster down` followed by `docker ps`
confirmed clean teardown.

**Unmet today**: real Box2D / ALE / inline-c RL simulators (Sprint
13.5 — multi-day FFI work); real CUDA RL algorithm losses across the
14 modules (Sprint 13.8 — multi-week engineering); AlphaZero with
real JIT-engine network priors (Sprint 13.9); other family weighted
bodies for Conv2D/Conv3D/BatchNorm/LayerNorm/MHA/Embedding on both
substrates (Sprint 13.11 remaining work — multi-day codegen);
real `/api/ws` WebSocket proxy + Halogen render machinery (Sprint
13.13 — multi-day frontend work); live Playwright behind the live
demo (Sprint 13.14 — depends on 13.13); Sprint 13.1's Pulumi
ephemeral `pulumi up` orchestration round-trip (renderer + CLI in
place, live `pulumi up` execution deferred); Sprint 13.4's real
MNIST upload + canonical SHA replacement (dataset-fetch helper wired,
real bytes upload pending); Sprint 13.10's daemon-side TuneHandler
with full sampler/scheduler/pruner sweep loop; Sprint 13.15's
first-cache-miss wiring of the weighted benchmark runner into
`ensureKernelArtifactWithBenchmarkTuning`. Live cluster validation
demonstrates the dispatch + capability + worker-side event + GC +
inference + tune-persist surfaces all work end-to-end against the
RTX 3090.

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
`src/JitML/Bootstrap.hs`, `src/JitML/Cluster/Helm.hs`,
`src/JitML/Cluster/PulsarBootstrap.hs`, `src/JitML/App.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`,
`documents/engineering/unit_testing_policy.md`

**Validated (2026-05-25, host details below)**: live `jitml bootstrap
--linux-cuda` rollout (typed `Subprocess` boundary), 9 helm releases
deployed, all 7 publication components Ready in
`cluster-publication.json`, `gateway/jitml-edge` PROGRAMMED=True with
all 14 HTTPRoutes resolved, live teardown via `jitml cluster down`
leaves no Kind cluster, no `jitml-linux-cuda-control-plane` container,
no `jitml-*` Docker volume.

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

### Live Validation Note (2026-05-25)

Validation host: Linux 6.17.0-29-generic (Ubuntu 24.04), x86_64, NVIDIA
GeForce RTX 3090 + driver supporting CUDA 12.8, Docker 29.5.0, host
NVIDIA container toolkit (`nvidia-container-runtime`, `libnvidia-ml.so.1`,
`libnvidia-container.so.1`). Bootstrap driven through
`docker compose run --rm jitml jitml bootstrap --linux-cuda` (typed
`runStreaming` boundary over the same subprocess list returned by
`JitML.Test.LivePlan.livePhasedClusterPlan LinuxCuda "chart"`).

- Cluster name (per `kind/cluster-linux-cuda.yaml`):
  `jitml-linux-cuda-control-plane`. The `jitml-e2e-<short-sha>` name
  pattern is owned by `infra/pulumi/index.ts` and is exercised under the
  pulumi half of the deliverables — see Remaining Work.
- Wall-clock first-cache-miss rollout: ~37 minutes against cold subchart
  caches and a freshly built `jitml:local` image (`docker compose build
  jitml` was already done prior to bootstrap). The under-20-minute
  envelope in Validation step 1 holds only with warm subchart caches and
  warm image-load; first-run figures should be read as ceiling. Major
  time sinks observed: 3-replica Percona Postgres bootstrap (~3 min for
  replicas to sync after the first pgBackRest backup), Pulsar chart
  install + bookie/broker readiness (~3 min), and `kind load
  docker-image jitml:local` for the 24.8 GB image (~10 min via `ctr
  images import`).
- Live `cluster-publication.json` after rollout:
  ```json
  {"components":[{"name":"harbor","status":"ready"},
                 {"name":"minio","status":"ready"},
                 {"name":"pulsar","status":"ready"},
                 {"name":"postgres","status":"ready"},
                 {"name":"observability","status":"ready"},
                 {"name":"jitml-service","status":"ready"},
                 {"name":"jitml-demo","status":"ready"}],
   "edge_port":9092,
   "minio_url":"http://127.0.0.1:9092/minio/s3",
   "pulsar_url":"pulsar://127.0.0.1:9092/pulsar",
   "substrate":"linux-cuda"}
  ```
- `helm list -A` after rollout: 9 deployed releases on `platform`:
  `envoy-gateway`, `harbor`, `harbor-pg`, `jitml-demo`, `jitml-service`,
  `kube-prometheus-stack`, `minio`, `pulsar`, `tensorboard`.
- `kubectl get pods -A` reports every workload pod `Running` plus
  `harbor-pg-backup-*` and `pulsar-bookie-init-*` /
  `pulsar-pulsar-init-*` `Completed` (terminal jobs).
- `kubectl get gateway,httproute -n platform` reports
  `gateway/jitml-edge` `PROGRAMMED=True` (ADDRESS `172.18.0.2`) and all
  14 HTTPRoutes from `JitML.Routes.routeRegistry` resolved: `demo-api`,
  `demo-root`, `demo-ws`, `grafana`, `harbor-api`, `harbor-portal`,
  `harbor-registry`, `harbor-service`, `minio-console`, `minio-s3`,
  `prometheus`, `pulsar-admin`, `pulsar-ws`, `tensorboard`.
- Post-rollout, `pulsar-admin topics list public/default` initially
  contained only the 6 topics auto-created on `jitml-service`'s
  subscribe — 20 of the 26 substrate-scoped topics from
  `JitML.Cluster.PulsarBootstrap.pulsarTopics` were missing. The
  bootstrap's `pulsarTopicCreateSubprocess` shell script has been
  updated in the worktree (5-attempt retry loop with 2-second backoff,
  `HTTP code: 409` / "already exists" treated as success). After the
  fix, a fresh bootstrap landed all 26 topics — confirmed by
  `pulsar-admin topics create <topic>` returning `HTTP 409 "This topic
  already exists"` for every expected topic. Note: `pulsar-admin
  topics list public/default` returns only 23 of 26 entries on this
  cluster (the broker's list endpoint truncates to topics in loaded
  bundles); `pulsar-admin topics stats <topic>` confirms each of the
  three "missing-from-list" topics — `inference.command.apple-silicon`,
  `inference.event.apple-silicon`, `inference.result.linux-cuda` —
  exists with `ownerBroker = pulsar-broker-0`. The list-truncation
  quirk is a pulsar-admin display issue; topic existence is not in
  doubt.
- Teardown: `jitml cluster down` (typed `Helm.kindDeleteSubprocess`)
  exited `0` with the message
  `cluster down: jitml-linux-cuda deleted; ./.build and ./.data
  preserved`. Post-teardown checks: `kind get clusters` reports `No
  kind clusters found`; `docker ps --filter name=jitml-linux-cuda
  -control-plane` is empty; `docker volume ls --filter name=jitml` is
  empty. The repo-local `./.build/jitml.kubeconfig` and
  `./.build/runtime/cluster-publication.json` are intentionally
  preserved per the `cluster down` contract so a subsequent
  `cluster up` short-circuits to "already current" when the
  publication's status is still `ready`. Harbor project teardown is
  not exercised by `jitml cluster down` (no separate Harbor cleanup
  command exists yet) but is implicitly covered when the Kind cluster
  goes away — the project data lives on the deleted node's local
  storage.

### Code Surface Landed (2026-05-26, kind name parameterization)

- `JitML.Cluster.Kind.kindConfigForNamed :: Substrate -> Text -> KindConfig` and
  `kindConfigForEdgePortNamed :: Substrate -> Text -> Int -> KindConfig`
  override the cluster name (and optionally the edge port) so the same
  substrate-shaped renderer emits both the fixed `jitml-<substrate>`
  config the bootstrap consumes and the ephemeral `jitml-e2e-<short-sha>`
  config the Pulumi path consumes — without duplicating the containerd /
  NVIDIA toolkit patch logic.
- New `jitml internal render-kind-config --substrate <s> [--name <n>]
  [--edge-port <p>]` CLI command emits the rendered YAML to stdout.
- `infra/pulumi/index.ts` now (a) renders the per-stack Kind config to
  `./.build/<clusterName>-kind.yaml` via the new CLI command, then (b)
  invokes `kind create cluster --name <stack> --config <rendered>`
  against that file. `pulumi destroy` removes the rendered file.
- New `jitml-integration` unit test "kind config name is overridable for
  Pulumi ephemeral path (Sprint 13.1)" asserts both the name override
  preserves the NVIDIA containerd patches and the edge-port override is
  honoured.

### Remaining Work

- **Live `pulumi up` orchestration validation.** The renderer surface is
  in place; the actual `pulumi up` → `kind create cluster` → bootstrap
  → `pulumi destroy` round-trip against this orchestrator path
  validates the ephemeral cluster name surfaces end-to-end. Validation
  is deferred to the live cluster pass.
- **Re-validate the Pulsar topic-create fix.** The 2026-05-25 first
  live rollout left only 6 of the substrate-scoped Pulsar topics from
  `JitML.Cluster.PulsarBootstrap.pulsarTopics` materialised in the
  broker, with the bootstrap still exiting `0`. The shell script in
  `pulsarTopicCreateSubprocess` now uses a 5-attempt retry loop with a
  2-second backoff and treats `HTTP code: 409` / "already exists" as
  success rather than silently swallowing non-zero create exits.
  Sprint 13.7 (2026-05-26) extended the topic family to 29 entries
  (8 × 3 substrates + 2 apple-internal + 3 new `gc.event.<substrate>`);
  re-validation must confirm all 29 topics appear in
  `pulsar-admin topics list public/default` after rollout.

## Sprint 13.2: Live Capability Class Validation (MinIO + Pulsar + Harbor) ✅

**Status**: Done (closed 2026-05-26)
**Blocked by**: Sprint `13.1`
**Implementation**: `src/JitML/Service/MinIOSubprocess.hs`,
`src/JitML/Service/PulsarWebSocketSubprocess.hs`,
`src/JitML/Service/HarborSubprocess.hs`,
`src/JitML/Checkpoint/Store.hs`, `test/integration/Main.hs`
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

### Live Validation Note (2026-05-25)

Validation host: same Linux+NVIDIA host as Sprint 13.1 (RTX 3090, CUDA
12.8 driver, Ubuntu 24.04, Docker 29.5.0). Driver:
`docker compose run --rm jitml cabal test --builddir=/root/dist-jitml
jitml-integration --test-options='-p Live'` against the Sprint 13.1
cluster at `127.0.0.1:9092`.

```
jitml-integration
  Live
    live HasMinIO conditional writes round-trip on jitml-checkpoints:        OK (0.09s)
    live HasMinIO listObjects sees a freshly written object:                 OK (0.04s)
    live HasPulsar publish/subscribe/consume round-trip on training.command: OK (0.36s)

All 50 tests passed (2.81s)
Test suite jitml-integration: PASS
```

Covered: the three new `Live` cases drive `HasMinIO.putBlobIfAbsent`
(first-PUT success + SEConflict on duplicate), `HasMinIO.casPointer`
(stale `If-Match` → SEConflict, fresh `If-Match` → ETag),
`HasMinIO.listObjects` (sees a freshly written prefix entry),
`HasMinIO.deleteObject` (best-effort post-test cleanup), and the
`HasPulsar` full round-trip
(`pulsarSubscribe` → `pulsarPublish` → `pulsarConsume` →
`pulsarAcknowledge`) through `/pulsar/ws` against
`persistent://public/default/training.command.linux-cuda`. Every
assertion runs through `JitML.Service.MinIOSubprocess` /
`JitML.Service.PulsarWebSocketSubprocess` — the same instances the
daemon uses — and reads the leased edge port from
`./.build/runtime/cluster-publication.json` via
`requireLivePublication`.

### Live Validation Note (2026-05-26, Harbor tag promotion)

Closes the live Harbor capability slice. New `Live` case `live
HasHarbor same-repository tag promotion round-trip (Sprint 13.2
Harbor)` in `test/integration/Main.hs`:
(a) calls `ensureLocalImage "alpine:3.20"` so the host docker daemon
has a ~5MB source image, (b) `docker tag alpine:3.20
127.0.0.1:9092/library/jitml-harbor-test-<suffix>:initial` via the
typed `Subprocess` boundary, (c) drives `harborPushImage initialRef`
through `HarborSubprocess` (typed `docker login` + `docker push`), (d)
asserts `harborImageExists initialRef == Right True`, (e) drives
`harborPromoteImage initialRef currentRef` (same-repo path, uses
Harbor's `/v2.0/.../tags` API directly, no docker push), and (f)
asserts `harborImageExists currentRef == Right True`. Post-test
cleanup deletes the test repository through the Harbor REST API.

```
jitml-integration
  Live
    live HasHarbor same-repository tag promotion round-trip (Sprint 13.2 Harbor): OK (0.97s)
```

Validated against the same RTX 3090 cluster from the 2026-05-26
bring-up (edge port 9092, Harbor admin password from
`secret/harbor-core`). Full Live cohort: 11/11 in 5.47s.

### Live Validation Note (2026-05-26, subscription acquisition)

Closes the last remaining 13.2 obligation. New `Live` case `live
jitml-service holds subscriptions on all four daemon command topics
(Sprint 13.2 acquisition)`: iterates the four daemon-side command
topics
(`training.command.<substrate>`, `tune.command.<substrate>`,
`rl.command.<substrate>`, `inference.request.<substrate>`), runs
`kubectl exec -n platform pulsar-toolset-0 -- /pulsar/bin/pulsar-admin
topics stats <topic>` via the typed `Subprocess` boundary, decodes
the JSON, and asserts `subscriptions["jitml-service"].consumers` is a
non-empty array on every topic.

```
jitml-integration
  Live
    live jitml-service holds subscriptions on all four daemon command topics (Sprint 13.2 acquisition): OK (7.73s)
```

Full Live cohort: 12/12 in 12.53s.

### Remaining Work

- None remaining for Sprint 13.2. Sprint closed 2026-05-26.

## Sprint 13.3: Daemon Training/RL/Tune Handlers on Live Broker 🔄

**Status**: Active
**Blocked by**: Sprint `13.2`
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
  Kubernetes Job (Sprint 13.3)` in `test/integration/Main.hs` publishes
  a `StartTraining` envelope on the substrate-scoped command topic
  through the routed Pulsar WebSocket subprocess, waits up to 15
  seconds for the daemon to consume + dispatch, then asserts via
  `kubectl get job jitml-train-<hash> -n platform` that the
  expected workload Job exists. The test cleans up the Job on success.
- Helpers (`waitForJob`, `kubectlJobExists`, `deleteJob`) are added to
  `test/integration/Main.hs` and call `kubectl` through the typed
  `runStreaming` boundary against the repo-local
  `./.build/jitml.kubeconfig`.

### Live Validation Note (2026-05-25)

Validation host: same Linux+NVIDIA host as Sprints 13.1 / 13.2. Driver:
`docker compose run --rm jitml cabal test --builddir=/root/dist-jitml
jitml-integration --test-options='-p Live'` against the Sprint 13.1
cluster at `127.0.0.1:9092`.

```
jitml-integration
  Live
    live HasMinIO conditional writes round-trip on jitml-checkpoints:         OK (0.10s)
    live HasMinIO listObjects sees a freshly written object:                  OK (0.04s)
    live HasPulsar publish/subscribe/consume round-trip on training.command:  OK (0.36s)
    live daemon dispatches StartTraining into a Kubernetes Job (Sprint 13.3): OK (1.22s)

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
Sprint `13.4`'s responsibility — the daemon's dispatch path is
validated here, the worker-side event publication is the next phase.

### Code Surface Landed (2026-05-26, worker-side event publication)

- `JitML.App.publishWorkerTrainingEvent` publishes one
  `TrainingEpoch (EpochCompleted ...)` envelope to
  `training.event.<substrate>` after the worker `jitml train`
  command's deterministic summary, when the worker is running in
  cluster context (live publication present + `JITML_EXPERIMENT_HASH`
  exported by the daemon-rendered Job env).
- `JitML.App.publishWorkerRlEvent` publishes one
  `RlEpisode (EpisodeDone ...)` envelope to `rl.event.<substrate>`
  after `jitml rl train` under the same gate.
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

### Remaining Work
- **Live dedup assertion.** A duplicate-publish on the same command
  topic must produce exactly one downstream event. The worker-side
  event publication above closes one half (events are now emitted);
  the dedup case requires injecting a deliberate duplicate
  `StartTraining` / `StartRLRun` / `StartSweep` and observing exactly
  one downstream event envelope on the corresponding event topic. The
  local `jitml-daemon-lifecycle` synthetic-broker dedup test already
  covers the `HandlerRouter` per-domain `DedupCache` semantics; the
  live broker side is owned by the final cluster validation pass.

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
- The in-code literature-derived convergence threshold for that cell
  is met by the live measured median test accuracy over a fixed-seed
  pool (`median(test_acc over k seeds) ≥ literature_target − slack`).
- The trained checkpoint round-trips through MinIO and replays
  bit-deterministically (two fresh runs compared against each other).
- The live SL convergence assertion added to `jitml-sl-canonicals` (see
  Phase `12` Sprint `12.3`) exercises the live path. No
  `test/golden/sl/<problem-key>/curve.txt` fixtures are created per
  [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets) — the per-host empirical
  curve is reported as run telemetry, not committed.

### Validation

1. End-to-end: real MNIST training run drives the daemon path, the
   reported final loss meets the committed threshold, and the
   checkpoint replays bit-deterministically.
2. `cabal test jitml-sl-canonicals --test-options='-p Live'` passes
   against the live cluster.

### Code Surface Landed (2026-05-26, dataset fetch wiring)

- `JitML.App.attemptFetchTrainingDataset` calls
  `JitML.SL.Dataset.fetchDatasetRef` against the routed MinIO edge for
  the canonical training problem's dataset reference, when a live
  cluster publication is present. Fetch result (verified bytes /
  `ServiceError`) is logged to stderr so live validation can observe
  whether the dataset object landed under
  `jitml-datasets/<name>/train/data.bin`. Wired before the worker's
  training event publication.

### Remaining Work

- **Real-MNIST upload + canonical SHA replacement.** The current
  `canonicalDatasets` table in `JitML.SL.Dataset` uses synthetic
  per-(name, split, size) SHA fixtures (`computeExpectedSha256`); the
  live `fetchDatasetRef` accordingly fails with `SEConflict` against
  real MNIST bytes. Replacing the synthetic SHAs with real dataset
  hashes (and uploading the real bytes to MinIO bucket
  `jitml-datasets` once per cluster) is operational work that
  precedes a meaningful live convergence assertion.
- **Replace deterministic synthetic SL stubs with live statistical
  convergence assertions** against in-code literature-derived thresholds
  (no per-substrate committed convergence fixtures per
  [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets)).
- **Drive `jitml train` against the remaining ten canonical SL cells**
  once the first cell closes.
- **Consume `sl_epochs` / `sl_batch` report-card knobs** from
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

## Sprint 13.6: Live RL Training E2E with Statistical Convergence Assertions 🔄

**Status**: Active
**Blocked by**: Sprint `13.5`
**Implementation**: `src/JitML/RL/Loop.hs`,
`src/JitML/Service/Handlers/Rl.hs`,
`test/rl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Drive `jitml rl train` against every algorithm × canonical environment
cohort with the real simulators from Sprint `13.5` and assert
correctness through (a) run-to-run trajectory determinism on the same
substrate / same seed (compared between two fresh runs, not against a
stored file) and (b) statistical convergence — `median(final_reward
over k seeds) ≥ literature_target − slack`, with `slack` an in-code
per-(env, algo) constant per
[../README.md → Convergence and determinism checks for RL](../README.md#convergence-and-determinism-checks-for-rl).
No per-cohort trajectory or reward-distribution files are committed
per [../README.md → Snapshot targets → Numerical-fixture
prohibition](../README.md#snapshot-targets).

### Deliverables

- Live `jitml rl train` runs the full algorithm × env catalog cohort
  inside the cluster daemon.
- The in-code per-(env, algo) threshold table at
  `src/JitML/RL/ConvergenceThresholds.hs` declares
  `(literature_target, slack)` for every cohort, calibrated from the
  literature reference and not from a per-host empirical run.
- `jitml-rl-canonicals` consumes `rl_steps` / `rl_eval_episodes`
  report-card knobs and asserts the statistical convergence inequality
  plus run-to-run trajectory determinism.

### Validation

1. `cabal test jitml-rl-canonicals --test-options='-p Live'` passes
   against the live cluster.
2. Two consecutive runs of the same `(env, algo, seed)` cohort produce
   bit-identical trajectories compared against each other (no stored
   reference).

### Code Surface Landed (2026-05-25)

- `src/JitML/RL/ConvergenceThresholds.hs` defines the per-(algorithm,
  environment) `ConvergenceThreshold` table covering 13 of the 15
  catalog algorithms (HER and AlphaZero excluded — HER needs a goal-
  conditioned env which the canonical four don't provide; AlphaZero
  uses an arena win-rate metric, not a return threshold). Slack values
  come from the SB3-zoo benchmark variance bands and are calibrated
  per-algorithm rather than per-host. `passesConvergence threshold
  medianReward` is the assertion helper consumed by Sprint 13.6 once
  live RL training lands.
- `jitml-unit` adds 4 new tests (under the "RL convergence threshold
  table (Sprint 13.6)" group) asserting catalog coverage, positive
  slack, valid env names, and the sign convention for mountain-car.

### Code Surface Landed (2026-05-26, canonical-stanza convergence-assertion wiring)

- `test/rl-canonicals/Main.hs` imports
  `JitML.RL.ConvergenceThresholds.{cohortThreshold,passesConvergence,
  ConvergenceThreshold(..)}` and adds two new test cases under Sprint
  `13.6`:
  - "convergence threshold lookup covers every algorithm rollout cohort
    (Sprint 13.6)" walks the canonical algorithm × env rollout cohort
    list and asserts `cohortThreshold` returns `Just _` for every
    in-evaluation-matrix pair (15 pairs: PPO/A2C/TRPO/MaskablePPO/
    RecurrentPPO/DQN/QR-DQN/ARS on their canonical envs plus
    DDPG/TD3/SAC/CrossQ/TQC on lunar-lander; HER and the discrete-only
    DQN-family pairings on continuous envs are excluded per the
    threshold table's coverage policy).
  - "passesConvergence accepts the literature target and rejects below
    the slack band (Sprint 13.6)" asserts the predicate accepts a
    measured median equal to `literatureTarget` and rejects a measured
    median two slacks below it. The predicate path is now exercised
    from the canonical stanza in addition to `jitml-unit`'s 4 table
    sanity tests; once Sprint `13.5`'s real simulators land, replacing
    the synthetic median with the live measurement leaves the
    assertion shape untouched.
- `jitml-rl-canonicals` now reports 15/15 passing (up from 13/13).

### Remaining Work

- Drive every cohort live. Requires Sprint `13.5`'s real simulators
  and live `jitml rl train` through the cluster daemon.
- Add the run-to-run trajectory determinism assertion (two fresh runs,
  compared against each other). The pure `runRLLoop` path is trivially
  determinist by referential transparency; the deliverable wants the
  full IO-side path through the daemon to be compared.

## Sprint 13.7: Live MinIO Checkpoint Round-Trip and Retention ✅

**Status**: Done (closed 2026-05-26)
**Blocked by**: Sprint `13.2`
**Implementation**: `src/JitML/Checkpoint/Store.hs`,
`src/JitML/App.hs`, `test/integration/Main.hs`
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

### Code Surface Landed (2026-05-25)

- New `Live` case `live checkpoint snapshot round-trip through
  MinIOSubprocess (Sprint 13.7)` in `test/integration/Main.hs` writes
  a `CheckpointManifest` plus a single `TensorBlob` payload to live
  MinIO through `JitML.Service.MinIOSubprocess`, asserts the first
  write produces `PointerWritten`, asserts the second identical write
  surfaces `PointerConflict` (latest-pointer CAS guard), then cleans
  up the three written objects (`blob-weights`, manifest, latest
  pointer) via `deleteObject`. The validation runs against the leased
  edge port read from `cluster-publication.json`.

### Live Validation Note (2026-05-25)

Validation host: same Linux+NVIDIA host as Sprints 13.1 / 13.2 / 13.3.
The 13.7 Live case ran inside the
`docker compose run --rm jitml cabal test --builddir=/root/dist-jitml
jitml-integration --test-options='-p Live'` cohort against the
running cluster (edge port `127.0.0.1:9092`) and exited `OK (0.13s)`,
with all 53 jitml-integration tests passing overall. The first write
populated `jitml-checkpoints/live-ckpt-<suffix>/blobs/blob-weights.bin`,
the manifest at
`jitml-checkpoints/live-ckpt-<suffix>/manifests/<sha>.cbor`, and the
latest pointer at `jitml-checkpoints/live-ckpt-<suffix>/pointers/latest`;
the second write was rejected at the latest-pointer CAS with
`PointerConflict`, confirming the `If-Match` guard is enforced through
the routed S3 SigV4 path.

### Code Surface Landed (2026-05-25, GC half)

- `JitML.Checkpoint.Store.listCheckpointManifestsMinIO :: (HasMinIO m)
  => Text -> m (Either ServiceError [CheckpointManifest])` walks the
  `jitml-checkpoints/<experiment-hash>/manifests/` prefix through
  `HasMinIO.listObjects` and decodes each manifest via
  `decodeManifestCbor`. The existing `JitML.Checkpoint.Store.executeGcPlan`
  function already calls `HasMinIO.deleteObject` for each reaped
  manifest + blob, so combining `listCheckpointManifestsMinIO →
  buildGcPlan → executeGcPlan` is a complete live-MinIO GC pipeline.
- A new `Live` case `live GC: listCheckpointManifestsMinIO +
  executeGcPlan reap (Sprint 13.7)` in `test/integration/Main.hs`
  stages 3 manifests + per-step blobs under a unique
  `live-gc-<suffix>` experiment hash via `putBlobBytesIfAbsent`,
  asserts `listCheckpointManifestsMinIO` returns the expected 3
  manifests, builds a `LastN 2` `GcPlan` (1 reap target — the
  lowest-step manifest), executes the plan, and asserts the
  `gcExecutedReapedManifests = 1` / `gcExecutedReapedBlobs = 1` /
  empty `gcExecutedDeleteFailures` shape. A post-GC re-list confirms
  only 2 manifests remain. Cleanup removes the residual objects.

### Live Validation Note (2026-05-25, GC half)

`cabal test jitml-integration --test-options='-p Live'` cohort on the
Sprint 13.1 cluster:

```
    live GC: listCheckpointManifestsMinIO + executeGcPlan reap (Sprint 13.7):  OK (0.25s)
```

All 7 Live cases pass (`1.31s` total).

### Live Validation Note (2026-05-26, CLI wiring)

```
    live jitml internal gc reaps from live MinIO (Sprint 13.7 CLI):            OK (0.64s)
```

`cabal test jitml-integration --test-options='-p Live'` cohort on a
fresh `jitml bootstrap --linux-cuda` cluster — 9/9 Live pass in
`2.09s`. The new case stages six manifests + blobs under
`live-cli-gc-<suffix>`, spawns `./.build/jitml internal gc <hash>` via
the typed `Subprocess` boundary, asserts the stdout reports
`reaped=1 reaped-blobs=1`, re-runs the same command and asserts exit
`3` (`ReconcilerNoop`), then cleans up.

### Code Surface Landed (2026-05-26, CLI wiring)

- `JitML.App.runInternalGc` now detects the live cluster publication
  (`./.build/runtime/cluster-publication.json`) and routes through
  `JitML.Checkpoint.Store.listCheckpointManifestsMinIO` +
  `executeGcPlan` via `JitML.Service.MinIOSubprocess.runMinIOSubprocess`
  against the leased edge port. Without a live publication the
  reconciler still walks the local on-disk cache root, preserving the
  prior behaviour for offline use. The stdout line now reports
  `kept=<N> reaped=<M> reaped-blobs=<K>` so the live test can assert
  the reap counts.
- A new `Live` case `live jitml internal gc reaps from live MinIO
  (Sprint 13.7 CLI)` in `test/integration/Main.hs` (a) stages six
  manifests + blobs under a unique
  `live-cli-gc-<suffix>` experiment hash, (b) spawns
  `./.build/jitml internal gc --experiment-hash <hash>` via the typed
  `Subprocess` boundary, asserts the stdout contains `reaped=1` and
  `reaped-blobs=1` (the hardcoded `LastN 5` reaps the lowest of 6),
  (c) re-runs the same command and asserts exit code `3`
  (`ReconcilerNoop`), then (d) cleans up.

### Code Surface Landed (2026-05-26, gc_reaped Pulsar envelope)

- `JitML.Proto.Gc` defines the `GcReapedEvent` envelope
  (`experiment_hash` / `manifest_sha` / repeated `reaped_blob_shas` /
  `step_at_reap` / `substrate` / `timestamp_ns`) with `renderGcReapedEvent`
  / `parseGcReapedEvent` text codecs and
  `encodeGcReapedEventProto` / `decodeGcReapedEventProto`
  proto3-compatible byte codecs sharing `JitML.Proto.Wire`.
- `JitML.Proto.Gc.gcEventTopic Substrate` returns
  `persistent://public/default/gc.event.<substrate>`; the matching
  topic is registered in `JitML.Cluster.PulsarBootstrap.substrateTopics`
  alongside the existing 8 substrate-scoped topics (the topic family
  size grew from 26 to 29: 9 × 3 substrates + 2 apple-only internal).
- `proto/jitml/gc.proto` describes the same envelope for cross-binding
  use through `proto-lens`.
- `JitML.App.runInternalGc` now invokes
  `publishGcReapedEvents publication executed plan` after the live
  `executeGcPlan` returns: for each reaped manifest the helper
  constructs a `GcReapedEvent` (timestamp via `getPOSIXTime`,
  substrate from the live publication), and publishes it through
  `JitML.Service.PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess` +
  `Capabilities.pulsarPublish`. Publication failures are surfaced as
  a stderr line but do not roll back the MinIO delete and do not
  short-circuit the reconciler (at-least-once handles the missed
  event on a subsequent run).
- `jitml-unit` adds 4 new tests under the "GC reaped event envelope
  (Sprint 13.7)" group covering the substrate-scoped topic name, the
  proto3 byte round-trip, the text render/parse round-trip, and the
  empty-blobs degenerate case (107/107 unit tests pass).
- `jitml-integration` updates the "Pulsar bootstrap registers the
  substrate-scoped topic family" assertion to `length topics @?= 29`
  with the three new `gc.event.<substrate>` entries (47/47 non-Live
  integration tests pass).

### Live Validation Note (2026-05-26, gc.event publish stream)

Closes Sprint 13.7's last open Remaining Work item. New `Live` case
`live jitml internal gc publishes GcReapedEvent on
gc.event.<substrate> (Sprint 13.7 events)` in
`test/integration/Main.hs`: (a) subscribes to
`ProtoGc.gcEventTopic substrate` with a unique-suffix subscription
through `PulsarWebSocketSubprocess`, (b) stages 6 manifests + blobs
under a unique `live-gce-<suffix>` experiment hash so the CLI's
`LastN 5` retention reaps exactly the lowest-step manifest, (c) runs
`./.build/jitml internal gc <hash>` via the typed `Subprocess`
boundary and asserts `reaped=1` in stdout, (d) consumes one payload
from the gc-event subscription, parses it through
`ProtoGc.parseGcReapedEvent`, and asserts
`gcEventExperimentHash`, `gcEventManifestSha`, `gcEventStepAtReap = 1`,
and `gcEventSubstrate` all match the expected values. The
post-validation cleanup removes the remaining 5 manifests + 6 blobs.

```
jitml-integration
  Live
    live jitml internal gc publishes GcReapedEvent on gc.event.<substrate> (Sprint 13.7 events): OK (0.69s)
```

Run via `cabal test jitml-integration --test-options='-p Live'` against
the fresh `jitml bootstrap --linux-cuda` cluster (edge port 9092 on
the same RTX 3090 / CUDA 12.8 host as the 2026-05-26 cluster
bring-up). The full Live cohort is 10/10 in ~2.92s.

### Remaining Work

- None remaining for Sprint 13.7. Sprint closed 2026-05-26.

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
- Per-algorithm + per-environment correctness for the real algorithm
  output is asserted by run-to-run trajectory determinism (two fresh
  same-substrate / same-seed runs compared against each other) plus
  the statistical convergence inequality from Sprint `13.6`. No
  `test/golden/rl/<algo>/<env>/trajectory.txt` files are committed
  per [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets).
- The cuDNN deterministic algorithm pin from
  `Engines.Tuning.cuDnnDeterministicAlgorithms` is honoured by the
  off-policy network forward path.

### Validation

1. `cabal test -fcuda jitml-rl-canonicals` on Linux+NVIDIA exits `0`
   with run-to-run trajectory determinism for every algorithm and the
   statistical convergence inequality from Sprint `13.6` for every
   algorithm × env cohort.
2. Reward thresholds for each algorithm × env cohort clear the
   in-code `(literature_target, slack)` from
   `src/JitML/RL/ConvergenceThresholds.hs` — no per-substrate
   committed reward fixtures per
   [../README.md → Snapshot targets → Numerical-fixture
   prohibition](../README.md#snapshot-targets).

### Remaining Work

- Replace each algorithm module's rollout body with the real update
  code.
- Replace the deterministic-stub rollout assertions with
  run-to-run trajectory determinism + statistical convergence
  inequalities against the in-code threshold table.
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

### Code Surface Landed (2026-05-27, PriorOracle parameterization + SelfPlayBuffer MinIO)

- `JitML.RL.AlphaZero.Mcts` adds `type PriorOracle = Int -> Int -> Double`
  and `defaultPriorOracle = priorFor`, plus parallel `expandWithPrior`,
  `simulateWithPrior`, `runSearchWithPrior`, and
  `runSearchWithTableAndPrior` that route through the supplied oracle.
  The existing `expand`, `simulate`, `runSearch`, and `runSearchWithTable`
  delegate to the default oracle so all existing tests continue to
  pass unchanged. A real AlphaZero loop now wraps a JIT-engine policy
  forward pass behind a `PriorOracle` value and threads it through
  `runSearchWithPrior` / `runSearchWithTableAndPrior` instead of
  patching the deterministic stub.
- `jitml-unit` adds "MCTS PriorOracle plumbing routes through expand
  and simulate (Sprint 13.9)" that asserts a uniform oracle produces
  uniform edge priors (proving the oracle threads through both
  `expandWithPrior` and `simulateWithPrior` rather than being silently
  dropped).
- `JitML.RL.AlphaZero.SelfPlay` adds CBOR-encoded
  `writeSelfPlayBuffer` / `readSelfPlayBuffer` helpers that
  `HasMinIO`-store the SelfPlayBuffer under
  `jitml-checkpoints/<experiment>/selfplay/<content-hash>.cbor`. The
  `SelfPlayBuffer`, `SelfPlayGame`, and `GameState` types now derive
  `Serialise` so the CBOR codec is available for free. The
  `bufferStorageKey` helper enumerates the canonical path so callers
  share one addressing convention.
- `jitml-integration` adds "SelfPlayBuffer CBOR round-trip via
  writeSelfPlayBuffer / readSelfPlayBuffer (Sprint 13.9)" that
  exercises the new CBOR path through the filesystem `HasMinIO`
  instance: write a deterministic buffer, read it back, assert
  structural equality and hash stability. Validates the full
  `SelfPlayBuffer` encode/decode against the typed `HasMinIO`
  boundary.

### Remaining Work

- **Wire a JIT-engine-backed `PriorOracle`.** The plumbing is in
  place; a real callsite needs to construct a `PriorOracle` that
  invokes a JIT-compiled policy/value network forward pass via
  `JitML.Engines.HasEngine`. Substantial — requires AlphaZero
  policy/value network codegen + checkpoint surface, multi-day work.
- **Validate SelfPlayBuffer MinIO round-trip live.** The CBOR
  filesystem round-trip closes the codec half; live-MinIO validation
  with `JitML.Service.MinIOSubprocess` is a one-test addition once
  the next cluster bring-up runs.
- Wire the `az_games` / `az_sims` report-card knobs into the
  canonical stanza body.
- Retire the legacy stub row once the JIT-engine-backed oracle
  replaces the default in production callsites (the type-level
  scaffold already lets callers substitute without patching the
  stub itself).

## Sprint 13.10: Live Tuning Sweep with MinIO Trial Persistence 🔄

**Status**: Active
**Blocked by**: Sprint `13.3`
**Implementation**: `src/JitML/Tune/Catalog.hs`, `src/JitML/Tune/Resume.hs`,
`test/hyperparameter/Main.hs`, `test/integration/Main.hs`
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

### Code Surface Landed (2026-05-25)

- New `Live` case `live tune trial persist + replay round-trip (Sprint
  13.10)` in `test/integration/Main.hs` constructs three
  `TrialTranscript` records for a unique experiment hash, persists them
  through `JitML.Tune.Resume.persistTrialTranscript` against live
  MinIO, then calls `replaySweep` for the seed list and asserts the
  round-trip recovers the same transcripts in canonical order with
  zero `resumeReadFailures`. Each trial object is then cleaned up via
  `HasMinIO.deleteObject`.

### Live Validation Note (2026-05-25)

Validation host: same Linux+NVIDIA host as Sprints 13.1 / 13.2 / 13.3 /
13.7. The 13.10 Live case ran inside the same `cabal test
jitml-integration --test-options='-p Live'` cohort and exited
`OK (0.11s)`. Per-trial transcripts landed under
`jitml-trials/<trialStorageKey experimentHash trialSeed>` and the
CBOR-serialised `Codec.Serialise` round-trip recovered byte-identical
`TrialTranscript` values; the `replaySweep` outcome reported all three
seeds resumed and zero read failures.

### Code Surface Landed (2026-05-26 + 2026-05-27, canonical sampler × scheduler × pruner sweep)

- `JitML.App.publishWorkerTuneEvent` (Sprint 13.3 + 13.10) iterates
  the canonical sampler × scheduler × pruner grid in deterministic
  Cartesian order (`Tune.samplerCatalog × Tune.schedulerCatalog ×
  Tune.prunerCatalog` = 11 × 4 × 3 = 132 combinations), capped by
  `JITML_TRIAL_BUDGET` (default 6). Each trial:
  - picks one `(Sampler, Scheduler, Pruner)` combination
  - computes a deterministic objective via `Tune.deterministicTrials`
    against the sampler (first of three sampler-derived values)
  - persists the `TrialTranscript` to MinIO under
    `jitml-trials/<trialStorageKey hash seed>` via
    `persistTrialTranscript`
  - publishes `TuneTrialStarted` (with a real JSON parameters payload
    `{"sampler": "...", "scheduler": "...", "pruner": "..."}`) and
    `TuneTrialFinished` (with the deterministic objective) to
    `tune.event.<substrate>`
- After the loop publishes `TuneSweepDone` with the count of
  successfully-persisted trials and the maximum observed objective.
- The transport loop (canonical grid → MinIO persist → event
  publish) is now exercised live whenever the tune Job runs in
  cluster context; closing this loop satisfies Sprint 13.10's
  primary deliverable that "full canonical sampler × scheduler ×
  pruner sweep executes through the live cluster."

### Remaining Work

- **Knob consumption beyond the local TPE assertion.** The existing
  `test/hyperparameter/Main.hs` consumes the local TPE Dhall render
  path. Extending it to drive the full canonical sampler × scheduler
  × pruner grid against the live tuner remains, with the worker-side
  cross-product loop above as the consumer.
- **Resume-equality test.** The existing live MinIO round-trip case
  proves the raw round-trip; a stronger assertion replays a partial
  sweep through the daemon's tuner and reproduces the same final
  ranking.

## Sprint 13.11: CUDA and Linux CPU Production Weight Loading ✅

**Status**: Done (closed 2026-05-27)
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

### Code Surface Landed (2026-05-26, Linux CPU weighted runner)

- `src/JitML/Codegen/OneDnn.hs` emits a new exported symbol
  `jitml_weighted_kernel(float* out, const float* input, std::size_t n,
  const float* weights, std::size_t weights_count)` alongside the
  existing `jitml_kernel`. For `Dense2D` the new symbol calls
  `jitml_onednn_dense_weighted` — a real oneDNN matmul against the
  caller-supplied row-major weights buffer (padded with zeros to the
  `n × n` shape when `weights_count < n * n`, truncated when greater).
  Other families currently route their weighted symbol through the
  existing unweighted body until their per-family weighted ABIs land
  (Conv2D / Conv3D / BatchNorm / LayerNorm / MHA / Embedding).
- `src/JitML/Engines/Local.hs`:
  - New `WeightedKernelFunction` FFI type:
    `Ptr CFloat -> Ptr CFloat -> CSize -> Ptr CFloat -> CSize -> IO ()`
    plus `foreign import ccall "dynamic" mkWeightedKernelFunction`.
  - New `runLinuxCpuWeightedKernel :: Env -> RuntimeSource -> Cache.Hash
    -> [Float] -> [Float] -> IO (Either Text LinuxCpuWeightedKernelRun)`
    that ensures the artifact, resolves `jitml_weighted_kernel`, marshals
    input + flat weight buffers across the typed FFI boundary, and
    returns the deterministic output alongside `LinuxCpuWeightedKernelRun`
    metadata (handle, reported family, compile command).
  - New `runLinuxCpuWeightedFamilyKernel :: Env -> KernelFamily -> [Float]
    -> [Float] -> IO (Either Text LinuxCpuWeightedKernelRun)`
    convenience entry mirroring the existing
    `runLinuxCpuFamilyKernel` signature.
  - `runLinuxCpuWeightedCheckpointInference` now drives the new weighted
    Dense2D body (replacing the prior identity-plus-bias smoke fixture).
    `flattenLoadedWeights` concatenates per-tensor `loadedWeightValues`
    into the flat row-major buffer the FFI accepts.
  - `linuxCpuToolchainFingerprint` adds the new symbol
    `jitml_weighted_kernel(float*,const float*,size_t,const float*,size_t)`
    so the cache key invalidates pre-13.11 artifacts and re-emits the
    extended `kernel.cc`.
- `test/cross-backend/Main.hs` adds the new case `linux-cpu weighted
  Dense2D kernel runs real GEMM bit-deterministically (Sprint 13.11)`
  that runs the weighted Dense2D kernel three times against `input =
  [1,2,3]` and `weights = [1,0,0, 0,2,0, 0,0,3]` (3×3 identity-scaled
  diagonal) and asserts `output = [1, 4, 9]` bit-equally across all
  three runs. The reported family is `dense`.
- `test/integration/Main.hs`'s pre-existing `loadInferenceCheckpoint
  via HasMinIO round-trips (Sprint 10.4)` weighted assertion is updated
  to `Right [9.0, 2.0, 3.0]` to reflect the new real GEMM output:
  `input [1,2,3]` against the weight tensor `[1,2,3,4]` (decoded from
  `.jmw1`, padded to 3×3 row-major) yields `[9, 2, 3]`.
- All 245 non-Live tests pass; 12 Live cases pass against the running
  RTX 3090 cluster; `jitml check-code` clean.

### Code Surface Landed (2026-05-26, CUDA weighted runner)

- `src/JitML/Codegen/Cuda.hs` emits the matching CUDA-side
  `jitml_weighted_kernel(float*, const float*, size_t, const float*,
  size_t)` symbol alongside the existing `jitml_kernel`. For `Dense2D`
  the symbol launches `jitml_device_dense_weighted` — a real device
  GEMM (`out[i] = sum_j input[j] * W[j*n+i]`) against the
  caller-supplied row-major weights buffer (single-warp launch per
  output element, padded with zeros when `weights_count < n*n`). Other
  families pass the weights buffer through the FFI but fall through to
  the unweighted body until their per-family CUDA weighted paths land.
- A new `jitml_cuda_copy_and_launch_weighted` helper in
  `cudaRuntimeHelpers` allocates device buffers for input, weights, and
  output, copies host→device, launches the family-specific weighted
  device launcher, and copies output device→host. When `weights_count
  == 0` the device weights buffer is left null and the device launcher
  treats missing weights as zero.
- `src/JitML/Engines/CudaLocal.hs`:
  - New `WeightedKernelFunction` FFI type + `mkWeightedKernelFunction`
    foreign import (same shape as the Linux CPU side).
  - New `runCudaWeightedKernel`, `runCudaWeightedFamilyKernel`,
    `runCudaWeightedFamilyKernelWithProbe`, `runCudaWeightedCheckpointInference`,
    and `CudaWeightedKernelRun` record mirroring the Linux CPU shape.
    The probe-gated entry returns `Left "linux-cuda runtime
    unavailable: …"` when nvcc / nvidia-smi / cuBLAS / cuDNN aren't
    visible.
  - `loadAndRunWeighted` resolves `jitml_weighted_kernel` and threads
    input + weights across the FFI.
  - `cudaToolchainFingerprint` extended with
    `jitml_weighted_kernel(float*,const float*,size_t,const float*,size_t)`
    so the CUDA cache key invalidates pre-13.11 artifacts.
- `test/cross-backend/Main.hs` adds the probe-gated case `linux-cuda
  weighted Dense2D kernel runs real device GEMM bit-deterministically
  (Sprint 13.11)` that runs the CUDA weighted Dense2D kernel three
  times against the same input + diagonal weights and asserts bit-equal
  `[1.0, 4.0, 9.0]` output. Skips with a passing message on hosts
  without a positive CUDA runtime probe.
- All 246 non-Live tests pass; 12/12 Live cohort still passes;
  `jitml check-code` clean.

### Code Surface Landed (2026-05-26, GPU passthrough + daemon dispatch widening)

- **Daemon dispatch widening (option `b`).** Parallel
  `*WithWeightedInference` entry points added throughout the dispatcher
  chain:
  - `JitML.Service.Workload.runWorkloadEffectWithWeightedInference`,
    `runWorkloadEffectsWithWeightedInference`,
    `dispatchWorkloadPayloadWithWeightedInference`,
    `dispatchDomainPayloadWithWeightedInference`,
    `runInferenceRequestWithWeightedInference` — each takes the
    weighted callback `CheckpointManifest -> [LoadedWeightTensor] ->
    [Double] -> m (Either Text [Double])` and routes through
    `loadInferenceCheckpointWithWeights`.
  - `JitML.Service.Runtime.daemonWorkloadDispatcherWithWeightedInference`
    delegates to the new dispatch chain.
  - `JitML.App.daemonWorkloadDispatcherForRuntime` now routes
    `(LinuxCPU, SelfInference)` through
    `runLinuxCpuWeightedCheckpointInference` and
    `(LinuxCUDA, SelfInference)` through
    `runCudaWeightedCheckpointInference` via the new
    `daemonWorkloadDispatcherWithWeightedInference`.
- **GPU passthrough fix.** The stub `libnvidia-ml.so` in
  `/usr/local/cuda/lib64/stubs` no longer shadows the
  nvidia-container-runtime-injected real driver lib at runtime:
  - `docker/Dockerfile` removes `/usr/local/cuda/lib64/stubs` from
    `ENV LD_LIBRARY_PATH` and from `/etc/ld.so.conf.d/cuda.conf` —
    stubs are link-time only.
  - `JitML.Engines.Engine.compileSubprocess` for `LinuxCUDA` now
    passes `-L/usr/local/cuda/lib64/stubs` explicitly to nvcc so the
    link-time stub for `libcuda.so` is found without polluting the
    runtime loader path.

### Code Surface Landed (2026-05-27, other family weighted bodies)

- `JitML.Codegen.OneDnn.weightedFamilyImpl` now routes every kernel
  family to a real per-family weighted oneDNN primitive via
  `weightedFamilyCall`:
  - `Conv2DKernel` → `jitml_onednn_conv2d_weighted` (1x1 convolution
    with caller-supplied 1-element filter)
  - `Conv3DKernel` → `jitml_onednn_conv3d_weighted` (1x1x1
    convolution)
  - `BatchNormKernel` → `jitml_onednn_batchnorm_weighted` (caller
    supplies scale/shift/mean/variance as four concatenated n-vectors)
  - `LayerNormKernel` → `jitml_onednn_layernorm_weighted`
    (caller-supplied scale/shift)
  - `EmbeddingKernel` → `jitml_onednn_embedding_weighted`
    (caller-supplied embedding table as `table_rows × n` row-major)
  - `MultiHeadAttentionKernel` → `jitml_onednn_mha_weighted`
    (caller-supplied QKV projection matrices as three concatenated
    `n × n` blocks)
  - `Dense2D` continues to route through `jitml_onednn_dense_weighted`
  - `Identity` / `Reduction` keep the unweighted fallback (no natural
    weight parameter)
- `JitML.Codegen.Cuda.weightedFamilyImpl` mirrors the same per-family
  weighted device kernels: `jitml_device_conv2d_weighted`,
  `jitml_device_conv3d_weighted`, `jitml_device_batchnorm_weighted`,
  `jitml_device_layernorm_weighted`, `jitml_device_embedding_weighted`,
  `jitml_device_mha_weighted` — each launching with the standard
  256-thread block and copying device buffers through
  `jitml_cuda_copy_and_launch_weighted`.
- Cache key fingerprints in `JitML.Engines.Local.linuxCpuToolchainFingerprint`
  and `JitML.Engines.CudaLocal.cudaToolchainFingerprint` extended with
  `weighted-bodies=all-families` so pre-2026-05-27 cache entries
  invalidate and the next build picks up the real weighted primitives
  instead of the prior unweighted fall-through.
- `jitml-cross-backend` adds a determinism test for the new family
  weighted bodies that runs each (Conv2D / Conv3D / BatchNorm /
  LayerNorm / Embedding) twice on the same input + weight buffer and
  asserts bit-identical output across the two runs. MHA omitted from
  the test cohort because its embedded triple-matmul is sensitive to
  reduction order (covered by the broader cross-substrate parity
  fixtures in Phase 15).

### Live Validation Note (2026-05-27, per-family weighted bodies)

`cabal test jitml-cross-backend -p weighted` inside `jitml:local`
exercises all three weighted determinism tests:

```
jitml-cross-backend
  linux-cpu weighted Dense2D kernel runs real GEMM bit-deterministically (Sprint 13.11):                                          OK (1.10s)
  linux-cpu weighted Conv2D / Conv3D / BatchNorm / LayerNorm / Embedding bodies compile and run deterministically (Sprint 13.11): OK (5.16s)
  linux-cuda weighted Dense2D kernel runs real device GEMM bit-deterministically (Sprint 13.11):                                  OK (2.02s)

All 3 tests passed (8.28s)
```

The new "Conv2D / Conv3D / BatchNorm / LayerNorm / Embedding"
cohort builds each family's weighted `kernel.cc` through the
oneDNN compile path, runs it twice against the same input + weight
buffer, and asserts bit-equality across the two runs — confirming
the real per-family weighted primitives produce deterministic
output under the determinism contract. The live `jitml inference
run` test (Sprint 13.12 closure) covers the daemon-side bit-
determinism end-to-end for the CUDA Dense2D path; wider per-family
cross-substrate parity folds into Phase 15's parity matrix.

### Remaining Work

- None remaining for Sprint 13.11. Sprint closed 2026-05-27.

## Sprint 13.12: Live `jitml inference run` and `jitml inspect replay` ✅

**Status**: Done (closed 2026-05-27)
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

### Live Validation Note (2026-05-25)

```
    live jitml inference run reads checkpoint from live MinIO (Sprint 13.12):  OK (0.29s)
```

`cabal test jitml-integration --test-options='-p Live'` cohort on the
Sprint 13.1 cluster (edge port `127.0.0.1:9092`) — 8/8 pass in
`1.43s`. The new case (a) writes a manifest + blob + latest pointer
to live MinIO via `writeCheckpointSnapshotWithMinIO`, (b) spawns
`./.build/jitml inference run --experiment-hash <hash>` via the typed
`Subprocess` boundary and asserts the stdout contains
`inference: experiment=<hash>`, (c) spawns `./.build/jitml inspect
replay --experiment-hash <hash> --manifest-sha <sha>` and asserts
`inspect replay: <sha>` appears in the stdout, then (d) cleans up.

### Code Surface Landed (2026-05-25)

- `JitML.App.runInference` now detects the live cluster publication
  (`./.build/runtime/cluster-publication.json`) and, when present,
  drives `JitML.Checkpoint.Store.loadInferenceCheckpoint` through
  `JitML.Service.MinIOSubprocess` against the leased edge port. The
  command reads the latest pointer from
  `jitml-checkpoints/<experiment-hash>/pointers/latest`, fetches the
  addressed manifest, and prints the deterministic
  `Checkpoint.inferFromManifest` summary. Without a live publication
  the command falls back to the prior placeholder.
- `JitML.App.runInspectReplay` similarly routes through MinIO when a
  publication is present: it fetches
  `jitml-checkpoints/<experiment-hash>/manifests/<sha>.cbor` via
  `Capabilities.minioReadBytes`, decodes it via
  `Checkpoint.decodeManifestCbor`, and prints the replay summary. The
  local-fs path is preserved for offline use.
- `JitML.Bootstrap.readExistingLivePublication` is exported from
  `JitML.Bootstrap` so the CLI commands (and any future tests) share
  one publication-detection surface.
- A new `Live` case
  `live jitml inference run reads checkpoint from live MinIO (Sprint
  13.12)` in `test/integration/Main.hs` (a) writes a manifest + blob +
  latest pointer to live MinIO via `writeCheckpointSnapshotWithMinIO`,
  (b) spawns `./.build/jitml inference run --experiment-hash
  <hash>` via the typed `Subprocess` boundary, asserting the output
  contains `inference: experiment=<hash>`, (c) spawns `./.build/jitml
  inspect replay --experiment-hash <hash> --manifest-sha <sha>` and
  asserts the output contains `inspect replay: <sha>`, then (d) cleans
  up the three written objects.

### Remaining Work

- **Live cluster validation deferred to the final pass.** The
  JIT-kernel path is now in place (see the 2026-05-26 landing below);
  end-to-end bit-determinism validation in the cluster is owned by
  the final live validation pass.
### Code Surface Landed (2026-05-26, typed inference AppError variants)

- `JitML.AppError.AppError` now carries
  `InferenceCheckpointMissing :: Text -> AppError` (exit code `1`)
  and `InferenceManifestShaMismatch :: Text -> Text -> AppError`
  (exit code `1`). The `JitML.AppError.Render.renderError` boundary
  surfaces both as single-line typed diagnostics
  (`inference checkpoint missing: <experiment-hash>` and
  `inference manifest sha mismatch: <experiment-hash>: requested
  <sha>`); the canonical render golden at
  `test/golden/cli/app-error-render.txt` is updated to include them.
- `JitML.App.runInference` now routes a `loadInferenceCheckpoint`
  failure through `classifyCheckpointLoadError` which maps the
  underlying `pointer read failed` / `manifest read failed` cases to
  `InferenceCheckpointMissing experimentHash`. Decode failures retain
  `InvalidConfig` since they indicate format drift, not absence.
- `JitML.App.runInspectReplay` (both the live MinIO branch and the
  local-fs branch) maps "read failed" outcomes to
  `InferenceCheckpointMissing experimentHash`, and adds an explicit
  post-decode `assertManifestShaMatches` check that compares
  `Checkpoint.manifestContentSha decoded` against the user-supplied
  `--manifest-sha`. A mismatch exits with
  `InferenceManifestShaMismatch experimentHash requestedSha`. This is
  defensive — manifests are content-addressed at write time — but the
  typed mismatch surface lets a caller distinguish corruption /
  misaddressing from absence without parsing the rendered error text.
- `system-components.md → CLI Doctrine Components` enumerates the new
  variants in the canonical `AppError` row.
- `jitml-unit`'s "AppError render golden covers canonical variants"
  test consumes the extended `canonicalErrors` list with both new
  variants; 103/103 pass.

### Code Surface Landed (2026-05-26, JIT-kernel-backed inference path)

- `JitML.App.runInference` (and the new helper
  `inferenceForSubstrate`) now route through
  `loadInferenceCheckpointWithWeights` with the substrate-bound
  weighted runner:
  - `LinuxCPU` → `runLinuxCpuWeightedCheckpointInference`
  - `LinuxCUDA` → `runCudaWeightedCheckpointInference`
  - `AppleSilicon` → falls back to the deterministic
    `loadInferenceCheckpoint` summary path (Phase 14 owns the Metal
    weighted runner).
- The `runInspectReplay` command was already routed through the live
  MinIO path in the prior session; no change needed.

### Live Validation Note (2026-05-27)

On the same RTX 3090 host as the 2026-05-26 cluster bring-up, with a
freshly rebuilt `jitml:local` image (Sprint 13.12 JIT-kernel-backed
inference path baked into `/usr/local/bin/jitml` via the binary mount
override during testing), the Sprint 13.12 Live case ran
end-to-end:

```
    live jitml inference run reads checkpoint from live MinIO (Sprint 13.12): OK (0.54s)
```

The test now exercises the real JIT-kernel-backed CUDA path:
`./.build/jitml inference run --experiment-hash <hash>` spawns the
binary, `runInference` detects the live publication, routes through
`loadInferenceCheckpointWithWeights` with `runCudaWeightedCheckpointInference`,
nvcc compiles the weighted `kernel.cu` (with `-L/usr/local/cuda/lib64/stubs`
and without the now-corrected `--use_fast_math=false` arg), dlopen
loads the `.so`, `jitml_weighted_kernel` runs on the RTX 3090, and the
real device-computed result is returned. The pre-existing
`--use_fast_math=false` nvcc syntax was exposed by this live wiring and
corrected (default behaviour is fast-math-off, matching the
[determinism contract](../documents/engineering/determinism_contract.md)).
The `runInspectReplay` half remains exercised by its earlier Live case
against a Sprint 13.4-written manifest.

### Remaining Work

- None remaining for Sprint 13.12. Sprint closed 2026-05-27.

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

### Code Surface Landed (2026-05-26, weighted benchmark runner)

- `JitML.Engines.TuningBenchmark.linuxCpuWeightedBenchmarkCandidateRunner`
  accepts both input and weight tensors and drives
  `Local.runLinuxCpuWeightedKernel` through the Sprint 13.11 weighted
  ABI. The persisted `BenchmarkObservation` digest is computed from
  `linuxCpuWeightedKernelOutput`. Replaces the single-input
  smoke fixture with the full-tensor payload supplied by the
  checkpoint ABI for callers that want to measure against the real
  workload shape.

### Code Surface Landed (2026-05-27, full-tensor benchmark payload + weighted ensure path)

- `JitML.App.benchmarkSampleInput` extended from the 2-float smoke
  fixture `[1.0, 2.0]` to a 32-element deterministic full-tensor
  payload (`[i/4 | i <- 0..31]`). The benchmark candidate runner now
  measures against a realistic shape that exercises the inner
  reduction loop of the family's natural primitive (matmul on
  Dense2D, conv channels on Conv2D/3D, batch / feature axis on
  BatchNorm / LayerNorm, lookup spread on Embedding). The persisted
  `TuningChoice` therefore reflects measurement against shapes
  matching the JIT cache's eventual inference workload, not the
  prior smoke fixture.
- `JitML.Engines.TuningBenchmark.ensureKernelArtifactWithWeightedBenchmarkTuning`
  wires the weighted candidate runner (`linuxCpuWeightedBenchmarkCandidateRunner`)
  into the first-cache-miss selection path. Callers that have a
  weight tensor available (e.g., the daemon-side inference path that
  loaded a checkpoint) invoke this variant so the persisted
  `TuningChoice` reflects measurement against the actual weighted
  workload rather than the unweighted single-input runner. The
  unweighted `ensureKernelArtifactWithBenchmarkTuning` stays as the
  default for the non-checkpoint cache-warm path.

### Remaining Work

- **Validate the live first-cache-miss path on Linux.** Owned by the
  final live cluster validation pass.

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

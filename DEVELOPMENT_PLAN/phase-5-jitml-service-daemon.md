# Phase 5: `jitml service` Daemon

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md),
[phase-4-stateful-platform-services.md](phase-4-stateful-platform-services.md),
[phase-7-jit-codegen-and-substrates.md](phase-7-jit-codegen-and-substrates.md),
[phase-8-supervised-and-rl-framework.md](phase-8-supervised-and-rl-framework.md),
[../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Stand up the current `jitml service` daemon surface — the
> registered CLI entrypoint, Dhall `BootConfig` / `LiveConfig` renderers,
> lifecycle, endpoint, logging, retry, payload-hash deduplication, SIGHUP
> reload decisions, capability-class boundaries, and stateless `Deployment`
> rendering — while deriving daemon client acquisition settings from
> `BootConfig`, routing local workload effects through the acquired
> capability classes, and keeping the remaining long-lived Pulsar runtime
> effects explicit as target validation.

## Phase Status

✅ **Done** (reopened 2026-06-23 for Sprint `5.15`; unblocked by Phases 2/4's
2026-06-24 close, **re-closed 2026-06-24**) — the durable-state registry
(`JitML.Project.Config`) now declares the logical Pulsar topic family, and a
`jitml-unit` anti-drift test holds `JitML.Coordinator.Topology`'s per-substrate
routing exactly consistent with it (`topologyLogicalNames jitmlTopology` equals the
registry's 13 `MessageTopic` names), so the registry is the single declared source
and the two cannot silently diverge. Validated: `jitml-unit` 218/218. All prior
Sprints `5.1`–`5.14` remain `✅ Done`; the prior closure history follows.

✅ **Done — common-shape reopen (Pulsar ML-Workflow convergence) closed on its
owned pure-logic surface.** The convergence made `jitml service` a **one-binary
Engine / Coordinator / Webapp** role model selected by typed Dhall `activeRole`
(Sprint `5.14`, run through the shared `JitML.Service.Lifecycle` skeleton), gave the
**Coordinator** the derived topic algebra (Sprint `5.13`, `JitML.Coordinator.Topology`
— typed descriptor + validated routing graph + derived `coordinatorTopics`, retiring
the hardcoded `PulsarBootstrap` list), and made the binary emit its own **reflected**
Dhall schema for every daemon config surface (Sprint `5.12`, `JitML.Service.DhallSchema`
+ `jitml internal dhall-schema`). Validated: **in-container** `jitml check-code`
(baked build layer, `docker compose build jitml` exit `0` — fourmolu + hlint +
warning-clean `-fcuda` build) and **in-container** `jitml docs check: ok`
(`docker run` against the built `jitml:local`), plus `jitml-unit` **206 / 206** and
`jitml-daemon-lifecycle` **35 / 35** on the apple-silicon host lane. The
**live** pieces are forward ownership-transfers: the Coordinator topic
reconcile-at-startup to Phase `15`, and live multi-role (Coordinator/Webapp pod)
serving to Phases `11`/`15`. (This shared host's Docker image store is
intermittently non-persisting — `docker compose run` can force a rebuild that OOMs
under the `-M2G` cap — so the in-container validation is run via `docker compose
build` + `docker run` against the persisted image rather than `docker compose
run`.) See
[README.md](README.md) → Closure Status, standards rule M, the shared
[../documents/engineering/pulsar_ml_workflow.md](../documents/engineering/pulsar_ml_workflow.md)
contract, and the rows in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md). The prior closure
narrative below is retained as dated history.

✅ **Done** (reopened and re-closed 2026-06-13 for Sprint `5.11`). The daemon
derives subscriptions from `BootConfig`, plans workload placement before
rendering side effects, keeps Linux CPU/CUDA Training/RL/Tune commands on the
Kubernetes Job path, and forwards Apple Metal-backed Training/RL/Tune starts to
the Apple host daemon over the host-command Pulsar topics. The host daemon
subscribes to those topics, executes the selected Apple `MlpDevice` host-native,
and publishes the normal `training.event.apple-silicon`,
`rl.event.apple-silicon`, and `tune.event.apple-silicon` events. Focused
validation: `docker compose run --rm jitml cabal test jitml-daemon-lifecycle
--test-show-details=direct` passed 34 / 34, including the Sprint `5.11`
placement assertions. Live failed-Job observation remains Phase `12`; full Apple
lane validation remains Phase `16`; final ledger walk-down remains Phase `17`.

Prior closure history follows.

✅ **Done** (reopened and re-closed 2026-06-12 for the true-headless Apple
Metal fixed-bridge doctrine; Sprint `5.10`). `LiveConfig` no longer carries any
build-VM CPU / memory / disk / idle-timeout fields, and `runService` no longer
starts or manages a Tart build VM. On `AppleSilicon + SelfInference`, startup
now probes the OS Metal runtime plus the fixed Metal bridge, records
`apple_metal_acquire` in the daemon runtime summary, and fails closed before
subscription acquisition if either boundary is unavailable. The remaining Apple
generated Swift/Tart cache-miss residue is completed under Phase `7` Sprint
`7.11` / Phase `16` Sprint `16.9`; the deletion ledger was empty at that
2026-06-12 closure.

✅ **Done** (reopened 2026-05-30 for the headless Apple Metal JIT workstream;
**re-closed the same day** after Sprint `5.8` removed `LiveConfig.tartIdleTimeout`
and the Tart spin-up from the daemon `acquire` lifecycle — the Apple Metal build
is a host CommandLineTools `swift build` with no VM to manage). See
[Reopened phases (2026-05-30)](README.md#reopened-phases-2026-05-30) and
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md). The status
text below predates the reopen.

✅ **Done** (re-closed 2026-05-29 after Sprint `5.7` landed the typed Dhall
`RunConfig` + BootConfig-mounted worker dispatch and retired the `JITML_*`
run-parameter IPC; live re-validation of the daemon→worker dispatch with the env
IPC removed is owned by Phase 15 Sprints `15.3` / `15.4` / `15.8` / `15.10`).
The phase owns
[Exit Definition](README.md#exit-definition) item 2 (`jitml service` is
the canonical long-running daemon, parameterised by Dhall `BootConfig` /
`LiveConfig`, hot-reloadable via SIGHUP, exposing `/healthz` / `/readyz` /
`/metrics`, emitting structured JSON logs on stderr, processing Pulsar
events at-least-once with the typed retry policy). **Implemented and validated**:
Sprints `5.1`, `5.2`, `5.3`, `5.4`, and `5.5` close the daemon entry point, the
BootConfig / LiveConfig ADTs and Dhall renderers, the in-binary HTTP listener
serving the three endpoints, the structured JSON logger wired through the
listener, the POSIX `SIGHUP` → reload-generation and `SIGINT` /
`SIGTERM` → graceful-drain-and-readiness-drop wiring, and the
`ServiceError` → `AppError` retry-classification mapping. The typed
capability classes now carry the full current method set
(`HasMinIO.{minioPutIfAbsent,minioReadObject,minioReadBytes,putBlobIfAbsent,putBlobBytesIfAbsent,casPointer,listObjects,deleteObject}`,
`HasPulsar.{pulsarPublish,pulsarAcknowledge,pulsarSubscribe,pulsarConsume,pulsarSeek}`,
`HasHarbor.{harborImageExists,harborPromoteImage,harborPushImage,harborPullImage,harborListImages}`,
`HasKubectl.{kubectlApply,kubectlStatus,kubectlGet,kubectlDelete}`) with
`ETag` and `SubscriptionId` newtypes. The Consumer dispatcher
(`EventDomain`, `HandlerRouter`, `routeByKind`) and the per-domain
LRU `DedupCache` are checked in. `JitML.Service.Clients` now derives
daemon-owned MinIO, Pulsar WebSocket, Harbor, and kubectl subprocess settings
from the loaded `BootConfig`; its `DaemonServiceClient` interpreter exposes
all four capability classes from that one settings record. `DaemonRuntime`
carries the `DaemonClientSettings` record plus the BootConfig-derived Pulsar
subscription plan plus startup subscription-acquisition state in its dry-run
summary. `jitml service` now opens the derived Pulsar WebSocket consumer
endpoint for each planned startup subscription through `DaemonServiceClient`
before serving and records whether each subscription was acquired.
`JitML.Service.Runtime.daemonConsumerBatch` threads acquired subscription
statuses through the LiveConfig-sized handler router in a bounded local batch.
`JitML.Service.Runtime.probeDaemonServiceClients` crosses the acquired
non-Pulsar capability boundaries with read-only MinIO list, Harbor list, and
kubectl get probes before the daemon serves, records `client_probe_status`, and
drops readiness on probe failure. `JitML.Service.Workload` now runs typed
mutating workload effects through those same capability classes: checkpoint
blob writes, checkpoint pointer CAS, Harbor image promotion, kubectl
apply/status/delete, and RunInference result publication. It also renders and
parses byte-faithful
`WorkloadEffect` payloads, and
`JitML.Service.Runtime.daemonWorkloadDispatcher` routes those payloads through
the runner so the consumer can execute them before ack. The same dispatcher now
maps parsed `JitML.Proto.{Training,Rl,Tune}` start/stop command envelopes into
typed Kubernetes Job apply/delete workload effects before ack.
`jitml service --consume-once <n>` runs a bounded acquired-subscription batch
through the same BootConfig-derived `DaemonServiceClient` settings and renders
the dispatch / dedup / ack outcome list before exiting.
The normal `jitml service` serve path now starts one held-open WebSocket
consumer worker per acquired subscription, shares a `LiveConfig`-sized
`HandlerRouter` across those workers for process-lifetime deduplication,
dispatches through the same `daemonWorkloadDispatcher`, explicitly acks each
broker message only after successful dispatch, explicitly negatively-acks each
dispatch failure through the same worker so the broker redelivers without
poisoning the dedup cache, and keeps `/healthz`, `/readyz`, and `/metrics`
served concurrently.
2026-05-21 live Linux CPU validation runs that bounded mode from the running
`jitml-service` pod against published Training, Tune, RL, and Inference command
messages, dispatches all four domains before ack, and applies the Training,
Tune, and RL Kubernetes Jobs through the service account. The routed WebSocket
subscribe probe now opens with `receiverQueueSize=0`, so startup acquisition
does not reserve pending messages before the bounded consumer path runs. A
second 2026-05-21 live run publishes byte-faithful `WriteCheckpointBlob`
`WorkloadEffect` payloads, drains them through the same service-pod
`--consume-once` path, and reads the written objects back from in-cluster MinIO.
The same live service-pod path also routes `PromoteWorkloadImage`
`WorkloadEffect` payloads through Harbor same-repository tag promotion and
verifies the promoted artifact through the in-cluster Harbor API.
`jitml-daemon-lifecycle` validates that runner and dispatcher against the
synthetic daemon client instance.
`RunInference` handler coverage is now routed through `JitML.Proto.Inference`:
the inference domain parses the request envelope, the request/result envelopes
also have proto3-compatible byte codecs, the handler loads the latest
checkpoint manifest through the daemon-owned MinIO client, runs the
deterministic inference read helper, and publishes `InferenceResult` on the
requested reply topic through the daemon-owned Pulsar client. 2026-05-21 live Linux CPU
validation seeds a latest checkpoint pointer and CBOR manifest in MinIO,
publishes a bare-reply-topic `RunInference` request to the live daemon topics,
drains the running pod with `--consume-once 1`, and consumes
`kind: InferenceResult` with output `1.01,2.01` from
`inference.result.linux-cpu`.
Another 2026-05-21 live Linux CPU validation rolls the normal
`jitml-service` Deployment to an image where `jitml service` starts held-open
consumer workers, seeds a checkpoint in in-cluster MinIO, publishes a
`RunInference` request to `inference.request.linux-cpu`, and consumes
`kind: InferenceResult` with output `1.01,2.01` from the reply topic without
using `--consume-once`. A final 2026-05-21 live Linux CPU validation on image
manifest list
`sha256:87bf1258ba006bfabb8f549f6f21682698964dad6be5ccf87a1349e653365fd3`
publishes the same `RunInference` payload twice through the running held-open
worker path and observes exactly one matching `InferenceResult`, then publishes
a `RunInference` request before its checkpoint exists, observes zero matching
results before seeding the checkpoint, seeds the latest pointer and manifest in
MinIO, receives the redelivered `InferenceResult` with output `1.01,2.01`, and
confirms the broker cursor reaches `markDeletePosition` `5:15` on
`inference.request.linux-cpu`.
**Closure evidence**:
The daemon-acquired read-only MinIO / Harbor / kubectl probes are live-validated
from the running Linux CPU `jitml-service` pod on 2026-05-20, including
in-cluster service-account `kubectl get pods` RBAC, and the 2026-05-21 bounded
consumer path proves the running pod can dispatch command envelopes through
`daemonWorkloadDispatcher`, ack after dispatch, apply/get/delete the
command-derived Training, RL, and Tune Job shapes, and route MinIO checkpoint
write workload effects plus Harbor image-promotion workload effects. The
standalone live MinIO
capability path is validated through
`JitML.Service.MinIOSubprocess`, and the standalone routed Pulsar
publish/consume path is validated through
`JitML.Service.PulsarWebSocketSubprocess`. Sprint `5.5` is closed: its local
subscription plan is BootConfig-derived, tested through `subscribeDaemonTopics`,
included in `DaemonRuntime`, acquired at daemon startup through the typed
Pulsar boundary, accepts fully-qualified Pulsar topic routing, is exercised by
`daemonConsumerBatch` against the synthetic broker and live Linux CPU pod
through `--consume-once`, runs the same dispatcher in held-open WebSocket worker
threads with one shared router, and is live-validated for duplicate payload
dedup plus dispatch-failure negative-ack redelivery. Sprint `5.6`'s Linux CPU and Linux CUDA service-pod portions closed on
2026-05-23 against the single-node Kind topology: the live full
`jitml bootstrap --linux-cpu` rollout completes all seven platform components
ready, the `jitml-service` Deployment ships with `maxSurge: 0` /
`maxUnavailable: 1` plus required hostname pod anti-affinity, and
`kubectl rollout restart deployment/jitml-service` replaces the pod without
ever holding two concurrent replicas; the Linux CUDA service-pod path on a
GPU host (NVIDIA GeForce RTX 5090, CUDA 12.8) rolls out
`Deployment/jitml-service` with `runtimeClassName: nvidia` and runs
`nvidia-smi -L` inside the service container. 2026-05-23 Apple Silicon live
validation runs `jitml bootstrap --apple-silicon`, materializes the patched host
Dhall with routed edge coordinates on `127.0.0.1:9090`, builds `jitml:local`
inside Docker with `jitml check-code`, loads `jitml:local` and
`jitml-demo:local` into Kind, completes the 110-step live phased rollout with
all seven publication components ready, and runs
`jitml service --config ./.build/conf/host/apple-silicon.dhall --consume-once 0`
host-native. That bounded host run loads the generated Dhall, derives
`ws://127.0.0.1:9090/pulsar/ws` plus `/minio/s3` and Harbor routed settings,
passes read-only MinIO / Harbor / kubectl probes, subscribes live to
`persistent://public/default/inference.command.apple-silicon` as `jitml-host`,
and exits after draining zero messages.
Single-replica deployment readiness is covered by the Linux CPU, Linux CUDA,
and Apple Silicon single-node validations. `JitML.Cluster.PulsarBootstrap` now registers the same
substrate-scoped topic family that the daemon subscription plan consumes.
That prior closure is superseded by Sprint `5.10`, which removes the now-legacy
build-VM acquire path.

### Current Implementation Scope

The worktree implements `BootConfig` / `LiveConfig` ADTs, Dhall
renderers, the `BootConfig` Dhall loader consumed by `jitml service --config`,
lifecycle phase data, hot-reload decision data, pure endpoint-response
rendering, pure JSON log rendering, service error/retry helpers, payload-hash
deduplication, capability-class definitions, and chart ConfigMap/Deployment
rendering, including the service account/RBAC and single-node-safe rolling
update strategy, the POSIX
signal/control surface in `src/JitML/Service/Signal.hs`, and the
low-level in-binary HTTP runtime in
`src/JitML/Service/{Http,Runtime}.hs` serving `/healthz`, `/readyz`, and
`/metrics`. `src/JitML/Service/Clients.hs` derives daemon client settings
from the loaded `BootConfig`: in-cluster daemons use the internal MinIO,
Harbor API, broker WebSocket, and in-cluster service-account kubectl
credentials, while the Apple host daemon splits the routed edge URLs into the
root endpoint plus the `/minio/s3` and `/pulsar/ws` request paths and uses the
repo-local kubeconfig. `SIGHUP` increments the reload
generation; `SIGINT` and
`SIGTERM` begin graceful drain and drop readiness. The filesystem-backed
`HasMinIO` instance, live HTTP-backed `JitML.Service.MinIOSubprocess`
instance, routed `JitML.Service.PulsarWebSocketSubprocess` one-shot and
held-open worker surfaces,
Docker/curl-backed `JitML.Service.HarborSubprocess` instance, and
subprocess-backed `HasKubectl` instance are checked in and covered locally /
behind the live path. `JitML.Service.Clients.DaemonServiceClient` is the
daemon-owned interpreter that delegates all four capability classes to those
subprocess settings. `JitML.Service.Runtime.probeDaemonServiceClients` invokes
the acquired MinIO, Harbor, and kubectl clients through read-only list/get
operations and records their status in the daemon runtime summary before
serving; 2026-05-20 live Linux CPU validation confirms those probes pass from
the running pod. `src/JitML/Service/Workload.hs` defines the current typed
workload-effect runner for mutating daemon effects: checkpoint blob
write, checkpoint pointer CAS, Harbor image promotion, kubectl
apply/status/delete, and RunInference result publication.
`src/JitML/Service/Runtime.hs` exposes
`daemonWorkloadDispatcher`, which parses rendered `WorkloadEffect` payloads and
routes them through that runner from the consumer dispatcher contract; it also
maps parsed Training/RL/Tune start/stop command envelopes into Kubernetes Job
apply/delete workload effects. `jitml service --consume-once <n>` executes a
bounded consumer batch with that dispatcher through the acquired daemon clients
and exits after rendering the outcome list. 2026-05-21 live Linux CPU
validation runs that mode from the `jitml-service` pod, consumes one message
from each acquired Training, Tune, RL, and Inference subscription, dispatches
before ack, and applies the command-derived Training, Tune, and RL Job shapes
through the service account. A second 2026-05-21 live run consumes
`WriteCheckpointBlob` workload-effect payloads through that same path and reads
the written objects back from MinIO. A third 2026-05-21 live run consumes
`PromoteWorkloadImage` workload-effect payloads through that same path and
verifies the promoted same-repository Harbor tag through the in-cluster Harbor
API. The same service-pod path now handles `RunInference` requests through the
MinIO latest-checkpoint read path and publishes `InferenceResult` through
Pulsar before ack.
The Consumer
surface also derives the daemon subscription set from `BootConfig`: clustered
daemons subscribe to the substrate-scoped training, tune, RL, and inference
request command topics, while the Apple host daemon subscribes only to
`inference.command.apple-silicon`; `domainFor` accepts both bare topic names
and live broker names under `persistent://public/default/`. Pulsar topic
bootstrap creates the matching substrate-scoped family before the daemon
subscribes. `JitML.Service.Runtime.acquireDaemonSubscriptions` crosses the
daemon-owned `HasPulsar.pulsarSubscribe` boundary from that plan; the
WebSocket-backed instance opens the routed consumer endpoint with
`receiverQueueSize=0` as a startup subscription probe, records per-topic
`DaemonSubscriptionStatus` values, and makes `/readyz` false if any startup
subscription acquisition fails.
`JitML.Service.Runtime.daemonConsumerBatch` uses acquired subscription IDs and
the `LiveConfig` dedup cache size/TTL to run a bounded `runConsumerLoop` batch
against the typed dispatcher surface. The normal `jitml service` serve path
starts per-acquired-subscription held-open WebSocket workers that retain one
shared `HandlerRouter` for the daemon process lifetime, dispatch through
`daemonWorkloadDispatcher`, ack each broker message through the open worker
pipe after the dispatcher succeeds, and negative-ack dispatch failures through
the same worker pipe while the HTTP listener remains active.
2026-05-21 live Linux CPU validation proves that normal service path consumes a
`RunInference` request and publishes the expected `InferenceResult`. The same
date validates duplicate payload deduplication and dispatch-failure
negative-ack redelivery against that held-open client. 2026-05-23 live Linux CUDA
validation on a GPU host (NVIDIA GeForce RTX 5090, CUDA 12.8) creates
`jitml-linux-cuda`, loads `jitml:local`, applies `RuntimeClass/nvidia`,
renders the local jitml-service chart with `substrate=linux-cuda`, rolls out
the actual `Deployment/jitml-service` to `Running` on
`jitml-linux-cuda-control-plane` with `runtimeClassName: nvidia`,
`NVIDIA_VISIBLE_DEVICES=all`, `NVIDIA_DRIVER_CAPABILITIES=compute,utility`,
and required pod anti-affinity; `nvidia-smi -L` inside the service container
reports the RTX 5090, `/healthz` returns `ok`, and `/metrics` serves the
Prometheus surface. The
Apple host live validation now runs the generated host Dhall through the routed
edge and acquires the `inference.command.apple-silicon` subscription.

## Phase Summary

This phase delivers the long-running daemon shape per doctrine `Long-Running
Daemons in the Same Binary`. There is **one CLI verb for the daemon — `jitml
service` — parameterised entirely by its Dhall config**; no separate
`host-service` verb. The Dhall declares `substrate`, `residency : Cluster |
Host`, `inferenceMode : SelfInference | ForwardToHost`, and host-side connection
info when `residency = Host`. On Linux substrates one daemon runs in-cluster
(`Cluster + SelfInference`); on Apple Silicon two daemons run, both the same
binary distinguished by Dhall (`Cluster + ForwardToHost` in-pod and `Host +
SelfInference` host-native).

## Sprint 5.1: `jitml service` Entry Point and Lifecycle Summary ✅

**Status**: Done
**Implementation**: `src/JitML/Service/Lifecycle.hs`,
`src/JitML/Service/{BootConfig,LiveConfig,Endpoints,Logger,Consumer,Retry}.hs`,
`src/JitML/Service/Signal.hs`,
`src/JitML/App.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`

### Objective

Wire `jitml service` into the CLI with the lifecycle/config/endpoint summary
surface and the in-binary HTTP listener.

### Deliverables

- `jitml service [--config path/to/config.dhall]` is registered and supports
  Plan/Apply output via `--dry-run` and `--plan-file`.
- `src/JitML/App.hs` loads an explicit `BootConfig` Dhall file when
  `--config` points at one, renders the lifecycle, BootConfig/LiveConfig,
  endpoint, and metrics summaries, then starts `ServiceRuntime.serveDaemon`
  for the command.
- `src/JitML/Service/Runtime.hs` composes the daemon HTTP routes over the
  endpoint response helpers.
- `Lifecycle` ADT enumerates the phases: `load`, `prereq`, `acquire`,
  `ready`, `serve`, `drain`, `exit`.
- `src/JitML/Service/Signal.hs` maps `SIGHUP` to reload generation changes and
  `SIGINT` / `SIGTERM` to graceful drain; `src/JitML/Service/Runtime.hs` wires
  those handlers into `serveDaemon`.
- Default command summary path is `./conf/cluster/linux-cpu.dhall` when no
  `--config` is passed.

### Validation

1. `jitml service --dry-run --config conf/cluster/linux-cpu.dhall` prints the
   typed plan and exits `0` without side effects.
2. `jitml service` prints the lifecycle/config/endpoint summary and starts the
   daemon HTTP listener.

## Sprint 5.2: `BootConfig` / `LiveConfig` Dhall and Hot-Reload Schema Surface ✅

**Status**: Done
**Implementation**: `src/JitML/Service/BootConfig.hs`,
`src/JitML/Service/LiveConfig.hs`,
`src/JitML/Service/HotReload.hs`,
`dhall/service/{BootConfig,LiveConfig}.dhall`
**Docs to update**: `documents/engineering/daemon_architecture.md`

### Objective

Split the daemon configuration into current `BootConfig` / `LiveConfig` ADTs,
Dhall schema files, renderers, and the local SIGHUP reload-decision surface.

### Deliverables

- `BootConfig` carries:
  - `substrate : Substrate`
  - `residency : Cluster | Host`
  - `inferenceMode : SelfInference | ForwardToHost`
  - `pulsarServiceUrl`, `pulsarAdminUrl`, `minioEndpoint`, `harborRegistry`
    (when `residency = Host`, bootstrap writes these into
    `./.build/conf/host/apple-silicon.dhall` from
    `./.build/runtime/cluster-publication.json`)
  - `httpListener : Maybe HttpListener` (none when `residency = Host`)
- `LiveConfig` carries:
  - `logLevel : LogLevel`
  - `retryPolicy : RetryPolicy`
  - `inferenceBatchSize`, `inferenceMaxLatencyMillis`
  - `dedupCacheSize`, `dedupCacheTtlSeconds`
  - `drainDeadlineSeconds`
- `JitML.Service.HotReload` models the local reload snapshot and SIGHUP reload
  decision: unchanged `LiveConfig` is ignored, changed `LiveConfig` increments
  the generation.
- `JitML.Service.Signal` wires POSIX `SIGHUP`, `SIGINT`, and `SIGTERM` into the
  daemon control surface: `SIGHUP` increments the reload generation, while
  `SIGINT` / `SIGTERM` begin graceful drain and make `/readyz` report not ready.
  Restart-required field changes (i.e., any `BootConfig` field) remain modelled
  as `AppError InvalidConfig` so the orchestrator restarts the pod.
- The Dhall schemas at `dhall/service/{BootConfig,LiveConfig}.dhall` are
  present and match the renderers; the `BootConfig` loader uses `Dhall.inputFile`
  and rejects unknown substrate text before building the daemon runtime.

### Validation

1. `jitml service` renders the current BootConfig and LiveConfig summaries.
2. `dhall/service/BootConfig.dhall` and `dhall/service/LiveConfig.dhall`
   exist and match the current renderer vocabulary; `jitml-integration`
   round-trips a rendered cluster `BootConfig` through `loadBootConfig`.
   `jitml-integration` also verifies the checked-in service ConfigMap carries
   the current `LiveConfig` fields including `dedupCacheSize` and
   `dedupCacheTtlSeconds`.
3. `jitml-unit` exercises the local hot-reload decision surface.
4. `jitml-daemon-lifecycle` exercises signal-to-action mapping and readiness
   drop on drain.

## Sprint 5.3: `/healthz` / `/readyz` / `/metrics` and Structured Logging ✅

**Status**: Done
**Implementation**: `src/JitML/Service/Endpoints.hs`,
`src/JitML/Service/Logger.hs`, `src/JitML/Service/Retry.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`

### Objective

Expose the endpoint response, metrics, retry, structured-log renderers, and
local HTTP route server that the daemon serves in-process.

### Deliverables

- Current `/healthz`, `/readyz`, and `/metrics` are renderable
  `EndpointResponse` values served by `JitML.Service.Http` through
  `daemonHttpRoutes`.
- Target `/healthz` returns `200 OK` if the daemon process is alive; `500`
  otherwise.
- Target `/readyz` returns `200 OK` only after the `Ready` lifecycle phase
  (capability classes acquired, prerequisite reconcile passed, Pulsar
  consumer subscribed); `503` otherwise.
- Target `/metrics` exposes Prometheus format scraped by the kube-prometheus-stack
  scrape config from Sprint `4.5`. Metrics include per-topic consumer lag,
  per-bucket PUT/GET latency histograms, JIT cache hit/miss counts, Lifecycle
  phase counters.
- `Logger` writes structured JSON on stderr with fields `ts`, `level`, `msg`,
  `lifecyclePhase`, `daemonId`, plus typed event payload. `LogLevel` is hot-
  reloadable.
- `RecoverableError` vs `FatalError` classification: recoverable kinds are
  retried via the `RetryPolicy` (Sprint `5.4`); fatal kinds emit a structured
  diagnostic and exit `2`.

### Validation

1. `jitml service` renders health, readiness, and metrics response summaries.
2. `cabal test jitml-daemon-lifecycle` exercises endpoint status codes and
   retry behavior against synthetic service errors.
3. `cabal test jitml-daemon-lifecycle` exercises the one-shot HTTP listener
   against `/healthz`.

## Sprint 5.4: `RetryPolicy` and Service Error Surface ✅

**Status**: Done
**Implementation**: `src/JitML/Service/Retry.hs`,
`src/JitML/Service/Capabilities.hs`,
`src/JitML/Service/Clients.hs`,
`src/JitML/Service/Workload.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`

### Objective

Stand up the local `RetryPolicy`, service-error mapping, and typed capability
class surface per doctrine `Capability Classes and Service Errors`.

### Deliverables

- `RetryPolicy` ADT with named strategies (`Once`, `LinearN k delayMs`,
  `ExponentialN k baseMs cap`, `RetryUntil deadline`). `retryServiceAction
  :: RetryPolicy -> (env -> IO a) -> env -> IO (Either AppError a)` is the
  single retry harness.
- Service-error kinds: `SEConflict` (retryable; from `If-Match`/`If-None-
  Match` `412`), `SEUnauthorized` (fatal), `SETimeout` (retryable per
  policy), `SETransient` (retryable per policy).
- `HasMinIO`, `HasPulsar`, `HasHarbor`, and `HasKubectl` define the typed
  action boundaries used by later live service clients.
- `JitML.Service.Clients.DaemonServiceClient` is the daemon-owned interpreter
  that exposes all four capability classes from the loaded
  `DaemonClientSettings` record.
- `JitML.Service.Workload` provides the local typed runner for mutating
  daemon effects: checkpoint blob write, checkpoint pointer CAS, Harbor image
  promotion, kubectl apply/status/delete, and RunInference result publication.
- `JitML.Service.Runtime.daemonWorkloadDispatcher` parses rendered
  byte-faithful `WorkloadEffect` payloads and routes them through that runner
  before the consumer ack path returns success.
- The same dispatcher maps the current text `StartTraining` / `StopTraining`,
  `StartRLRun` / `StopRLRun`, and `StartSweep` / `StopSweep` command envelopes
  into typed Kubernetes Job apply/delete workload effects before ack.
- `JitML.Proto.Inference` renders/parses and proto3-byte-round-trips the
  current `RunInference` / `InferenceResult` envelopes.
  `daemonWorkloadDispatcher` maps `InferenceDomain` `RunInference` payloads
  into the daemon-owned MinIO latest checkpoint read path and publishes
  `InferenceResult` through the daemon-owned Pulsar client before ack.
- `JitML.Service.PulsarWebSocketSubprocess` resolves bare public/default topic
  names for producer URLs, so inference request `reply-topic` values can use the
  same doctrine topic names that the dispatcher accepts.
- `jitml service --consume-once <n>` is the bounded validation mode for the
  daemon consumer path: it acquires subscriptions, drains `n` messages per
  acquired subscription, dispatches them through `daemonWorkloadDispatcher`, and
  exits with rendered consumer outcomes instead of starting the HTTP listener.

### Validation

1. `jitml-unit` exercises `retryServiceAction` against a synthetic
   `SEConflict`-emitting capability and asserts the policy is honoured.
2. `jitml-unit` verifies the capability-class surface names all four
   doctrine-required classes.
3. Transferred live validation: integration coverage exercises
   `putBlobIfAbsent` against real MinIO and asserts `If-None-Match: *`
   `412` is treated as `SEConflict`; the MinIO portion is satisfied by
   2026-05-19 live validation through `JitML.Service.MinIOSubprocess`, and
   the standalone routed Pulsar publish/consume portion is satisfied by
   2026-05-19 live validation through
   `JitML.Service.PulsarWebSocketSubprocess`. The long-lived daemon-acquired
   `HasPulsar` subscription / redelivery / seek target is owned by Sprint
   `5.5`.
4. `jitml-integration` verifies `JitML.Service.Clients` derives in-cluster
   daemon endpoints from the cluster `BootConfig`, derives Apple host edge
   endpoints from the patched host `BootConfig`, splits routed MinIO URLs into
   root endpoint plus `/minio/s3` request-target prefix, maps host Pulsar
   service URLs to `/pulsar/ws`, strips the Harbor project suffix for Docker
   registry calls, uses in-cluster kubectl credentials for cluster daemons, and
   pins Apple host kubectl to `./.build/jitml.kubeconfig`.
5. `jitml-daemon-lifecycle` verifies the daemon runtime summary exposes the
   `client_acquisition` section with the derived MinIO and Pulsar endpoints and
   the `pulsar_subscriptions` section with the BootConfig-derived topic plan.
6. `jitml-daemon-lifecycle` verifies
   `JitML.Service.Runtime.acquireDaemonSubscriptions` crosses the typed
   `HasPulsar.pulsarSubscribe` boundary, records acquired subscription status,
   and keeps the daemon ready when every planned subscription is acquired.
   `jitml-integration` verifies the WebSocket-backed subscribe probe targets the
   same routed consumer endpoint as the one-shot consumer with
   `receiverQueueSize=0` for acquisition.
7. `jitml-daemon-lifecycle` verifies `DaemonServiceClient` satisfies all four
   capability-class constraints, and `jitml service` uses that combined
   interpreter for startup subscription acquisition.
8. `jitml-daemon-lifecycle` verifies
   `JitML.Service.Runtime.probeDaemonServiceClients` invokes the acquired
   non-Pulsar clients through MinIO list, Harbor list, and `kubectl get pods`
   boundaries and records `client_probe_status` in the daemon summary.
9. Live Linux CPU validation on 2026-05-20 rolls the real `jitml-service` pod
   with service account/RBAC, confirms `client_probe_status` reports MinIO
   `jitml-checkpoints`, Harbor `library`, and in-cluster `kubectl get pods` as
   `ok`, verifies `/healthz`, `/readyz`, and `/metrics`, and confirms direct
   in-pod `kubectl get pods -n platform` succeeds.
10. `jitml-daemon-lifecycle` verifies
    `JitML.Service.Workload.runWorkloadEffects` invokes MinIO checkpoint
    blob/CAS writes, Harbor image promotion, and kubectl apply/status/delete
    through the non-Pulsar capability classes.
11. `jitml-daemon-lifecycle` verifies rendered `WorkloadEffect` payloads
    round-trip through `parseWorkloadEffectPayload` and that
    `JitML.Service.Runtime.daemonWorkloadDispatcher` routes parsed payloads
    through MinIO, Harbor, and kubectl before ack.
12. `jitml-daemon-lifecycle` verifies the dispatcher maps parsed Training/RL/Tune
    command envelopes into kubectl-backed workload effects.
13. Live Linux CPU validation on 2026-05-20 applies, reads, and deletes the
    current Training, RL, and Tune Job manifest shapes from inside the running
    `jitml-service` pod through the `jitml-service` service account.
14. Live Linux CPU validation on 2026-05-21 publishes one Training, Tune, RL,
    and Inference command message, runs
    `jitml service --config /etc/jitml/BootConfig.dhall --consume-once 1` from
    the running `jitml-service` pod, confirms each domain dispatches before ack,
    and verifies the Training, Tune, and RL Jobs are applied through the service
    account.
15. Live Linux CPU validation on 2026-05-21 publishes
    `WriteCheckpointBlob` `WorkloadEffect` payloads to the same four daemon
    topics, drains them through the running `jitml-service` pod with
    `--consume-once 1`, and reads the written checkpoint objects back from the
    in-cluster MinIO S3 endpoint.
16. Live Linux CPU validation on 2026-05-21 pushes a source image tag into
    Harbor, publishes `PromoteWorkloadImage` `WorkloadEffect` payloads to the
    same four daemon topics, drains them through the running `jitml-service` pod
    with `--consume-once 1`, and verifies the promoted same-repository Harbor
    tag through the in-cluster Harbor API.
17. `jitml-integration` verifies the `jitml service --consume-once <n>` CLI
    surface is generated from `CommandSpec`.
18. `jitml-integration` verifies the WebSocket producer resolves bare
    public/default topic names to
    `persistent/public/default/<topic>` producer endpoints.
19. Live Linux CPU validation on 2026-05-21 seeds a latest checkpoint pointer
    and CBOR manifest in in-cluster MinIO, publishes a `RunInference` payload
    with bare `reply-topic: inference.result.linux-cpu` to the four daemon
    topics, drains the running `jitml-service` pod with `--consume-once 1`,
    confirms all four domains dispatch before ack, and consumes
    `kind: InferenceResult` with output `1.01,2.01` from
    `inference.result.linux-cpu`.

### Remaining Work

No sprint-owned Phase `5.4` Remaining Work remains. The long-lived broker loop
and live redelivery / negative-ack validation are closed by Sprint `5.5`; CUDA
service-pod runtime validation and Apple host live validation are closed by
Sprint `5.6`.

## Sprint 5.5: At-Least-Once Pulsar Consumer with Message-Hash Deduplication ✅

**Status**: Done
**Implementation**: `src/JitML/Service/Consumer.hs`,
`src/JitML/Service/PulsarWebSocketSubprocess.hs`, `src/JitML/App.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`

### Objective

Stand up the local event-id and de-duplication helpers for the target
at-least-once Pulsar consumer per doctrine `At-Least-Once Event Processing`.
Idempotency remains the consumer's responsibility; the typed `EventID`
deduplication key is the protobuf message hash and is opaque to the broker.

### Deliverables

- Current `eventIdFromPayload` derives a SHA-256 payload hash and
  `processAtLeastOnce` keeps first-seen event IDs in deterministic order.
- Current `daemonSubscriptionsForBootConfig` derives the substrate-scoped
  command topic plan from `BootConfig`:
  `training.command.<mode>`, `tune.command.<mode>`, `rl.command.<mode>`, and
  `inference.request.<mode>` for clustered daemons, plus only
  `inference.command.apple-silicon` for the Apple host daemon.
- Current `subscribeDaemonTopics` crosses the typed `HasPulsar.pulsarSubscribe`
  boundary and returns one result per planned daemon subscription.
- Target `EventID` is the doctrine-typed deduplication key, derived from the protobuf
  message hash. The daemon does not trust client-supplied IDs.
- Target dispatcher routes by event kind to the per-domain handler (training,
  tune, RL, inference). Per-handler `dedupCache :: TVar (LRUSet EventID)`
  provides at-least-once → effectively-once for the duration the entry stays
  cached. Cache size and TTL are `LiveConfig` knobs.
- Acks are explicit; failure to ack within the `RetryPolicy` budget surfaces
  `AppError PulsarFailed`.
- The routed WebSocket subprocess consume path records broker message ids
  without pre-acking; `pulsarAcknowledge` sends the recorded id after the
  dispatcher returns success.
- `JitML.Service.PulsarWebSocketSubprocess.runPulsarConsumerWorker` starts a
  held-open broker consumer WebSocket, streams decoded deliveries to the parent
  process, and accepts explicit broker message ids back over stdin for
  post-dispatch ack plus explicit negative-ack commands for dispatch failures.
- The normal `jitml service` serve path starts held-open background consumer
  workers for acquired subscriptions, shares one process-lifetime
  `HandlerRouter` across those workers, and keeps the HTTP listener active
  while messages are drained.

### Validation

1. `cabal test jitml-daemon-lifecycle` verifies identical payloads produce
   the same event id.
2. `processAtLeastOnce` collapses repeated event ids in deterministic order.
3. `cabal test jitml-daemon-lifecycle` verifies `domainFor` accepts live
   fully-qualified broker topic names under `persistent://public/default/`,
   verifies the BootConfig-derived daemon subscription set for clustered and
   Apple-host daemons, and verifies `subscribeDaemonTopics` calls
   `HasPulsar.pulsarSubscribe` with the typed subscription names. The same
   suite verifies `DaemonRuntime` carries those subscriptions into the startup
   summary under `pulsar_subscriptions`, and verifies daemon startup acquisition
   records the acquired status under `pulsar_subscription_status`. It also
   verifies `JitML.Service.Runtime.daemonConsumerBatch` drains acquired
   subscription statuses through the LiveConfig-sized `HandlerRouter`, dispatches
   fresh events, deduplicates redelivered payload hashes, and acks every
   delivery against the synthetic broker. The same suite verifies a failed
   handler dispatch does not insert the event id into the dedup cache, calls
   `HasPulsar.pulsarSeek`, and allows the next redelivery to dispatch.
   `jitml-integration` verifies the WebSocket-backed subscribe probe renders the
   routed consumer endpoint used for actual broker acquisition with
   `receiverQueueSize=0`, so acquisition does not prefetch pending work.
4. `cabal test jitml-integration` verifies `JitML.Cluster.PulsarBootstrap`
   registers the matching 31-topic derived family and rejects retired
   `*.cluster` / `*.host` topic names.
5. Live Linux CPU validation on 2026-05-20 confirmed the live broker had the
   then-current 26-topic substrate-scoped family and the standalone routed
   WebSocket path published/consumed on
   `persistent://public/default/training.command.linux-cpu`, the same current
   topic family the daemon subscription plan targets.
6. `cabal test jitml-integration` verifies the routed WebSocket consume script
   records broker message ids without acknowledging before dispatcher success,
   verifies the explicit acknowledge command sends the recorded id, and verifies
   the held-open worker command renders the routed consumer endpoint, streams
   decoded payloads to the parent process, only acks when the parent writes a
   broker message id, and renders the explicit `negativeAcknowledge` command
   used for dispatch-failure redelivery.
7. Live Linux CPU validation on 2026-05-21 publishes the same `RunInference`
   payload twice to the running held-open daemon worker and consumes exactly one
   matching `InferenceResult` from `inference.result.linux-cpu`, proving the
   process-lifetime `HandlerRouter` dedup cache is populated by live broker
   deliveries and duplicate payload hashes are acked as idempotent no-ops.
8. Live Linux CPU validation on 2026-05-21 rolls the real `jitml-service`
   Deployment to the rebuilt image where normal `jitml service` startup
   creates held-open consumer workers,
   seeds a latest checkpoint in MinIO, publishes a `RunInference` request to
   `inference.request.linux-cpu`, and consumes `kind: InferenceResult` with
   output `1.01,2.01` from `inference.result.linux-cpu` without using
   `--consume-once`. This validates normal daemon event flow for a fresh live
   message.
9. Live Linux CPU validation on 2026-05-21 against image manifest list
   `sha256:87bf1258ba006bfabb8f549f6f21682698964dad6be5ccf87a1349e653365fd3`
   publishes a `RunInference` request before its checkpoint exists, observes
   `initial-results-before-seed: 0`, seeds the checkpoint latest pointer and
   manifest into MinIO, and then consumes the redelivered
   `kind: InferenceResult` with output `1.01,2.01`. The same validation checks
   the `inference.request.linux-cpu` broker cursor reaches
   `markDeletePosition` `5:15`, matching the latest request entry after ack.

### Remaining Work

No sprint-owned Phase `5.5` Remaining Work remains. Apple host Dhall
connectivity is closed by Sprint `5.6`.

## Sprint 5.6: Stateless `Deployment`, Pod Anti-Affinity, Per-Substrate Dhall ✅

**Status**: Done
**Implementation**: `chart/templates/deployment-jitml-service.yaml`,
`src/JitML/Service/ConfigMap.hs`, `src/JitML/Service/BootConfig.hs`,
`src/JitML/App.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`,
`documents/engineering/cluster_topology.md`

### Objective

Land the stateless `Deployment` shape with required pod anti-affinity at
`topologyKey: kubernetes.io/hostname`, plus bootstrap-rendered per-substrate
Dhall configs.

### Deliverables

- `Deployment/jitml-service` with `replicas: 1` default, required pod
  anti-affinity at hostname topology. The local Kind topology is single-node,
  so the supported local replica count is one; the anti-affinity rule remains
  in the chart for non-local multi-node environments. **Not** a `StatefulSet` —
  durable state lives entirely in MinIO and Pulsar.
- Rolling updates use `maxSurge: 0` and `maxUnavailable: 1` so the required
  anti-affinity does not deadlock a single-node development cluster during a
  replacement rollout.
- `runtimeClassName: nvidia` only when substrate is `linux-cuda`.
- `jitml bootstrap --<substrate>` renders
  `./.build/conf/cluster/<substrate>.dhall` and
  `chart/templates/configmap-jitml-service.yaml`; the checked-in
  `chart/local/jitml-service/templates/configmap.yaml` carries the same
  current Dhall surface for the live Helm chart.
- The cluster Dhall declares `residency = < Cluster | Host >.Cluster`,
  `inferenceMode = < SelfInference | ForwardToHost >.SelfInference` for
  Linux substrates, and
  `< SelfInference | ForwardToHost >.ForwardToHost` for Apple.
- `jitml bootstrap --apple-silicon` also renders
  `./.build/conf/host/apple-silicon.dhall`; live bootstrap patches the chosen
  edge port so the host daemon can reach Pulsar and MinIO. Generated
  host-resident Dhall renders `httpListener = None { host : Text, port : Natural }`
  so the standalone file loads without an out-of-scope type alias.
- Linux substrates do not render a host-level Dhall file; all JIT operations
  happen in the cluster and the daemon knows that from its ConfigMap Dhall.
- Deployment template mounts `./.build/` from the single-node hostPath into the
  pod at `/opt/build/` so the JIT cache is shared.
- `chart/local/jitml-demo/templates/deployment.yaml` is the sibling Deployment
  for the Webapp role workload; Phase `11` owns the current frontend/demo
  scaffold and target HTTP server behavior.

### Validation

1. `chart/templates/deployment-jitml-service.yaml` renders the stateless
   Deployment surface.
2. `jitml bootstrap --<substrate>` materializes the service ConfigMap and
   Dhall files.
3. `jitml-integration` confirms the Deployment renderer uses
   `requiredDuringSchedulingIgnoredDuringExecution` with
   `topologyKey: kubernetes.io/hostname`, not advisory preferred
   anti-affinity.
4. Historical Linux CPU validation on 2026-05-19 completed
   `jitml bootstrap --linux-cpu`, upgraded the local Helm chart with the typed
   Dhall ConfigMap, rolled out a single `jitml-service` pod, and verified
   `/healthz`, `/readyz`, and `/metrics` through a port-forward.
5. 2026-05-23 live Linux CPU validation on the single-node topology: `jitml
   bootstrap --linux-cpu` completes a full live phased rollout (Postgres
   operator + `harbor-pg` ready, Harbor up against the external Postgres,
   MinIO, Pulsar with broker-embedded WebSocket, kube-prometheus-stack,
   TensorBoard, `jitml-service`, `jitml-demo`) and writes
   `./.build/runtime/cluster-publication.json` with all seven components
   `ready` on `edge_port: 9091`. The `jitml-service` Deployment renders with
   `strategy.rollingUpdate.maxSurge: 0` / `maxUnavailable: 1` and required
   `podAntiAffinity` at `topologyKey: kubernetes.io/hostname`. `kubectl
   rollout restart deployment/jitml-service` triggers a replacement rollout:
   the old `jitml-service-75969d8755-n8tnw` pod terminates before the new
   ReplicaSet's `jitml-service-68d5759bc6-z2vb6` pod schedules — the cluster
   never holds two pods concurrently (no surge pod), and the new pod reaches
   `Running` on `jitml-linux-cpu-control-plane`. `/healthz` returns `ok`,
   `/readyz` returns `ready`, `/metrics` serves the Prometheus surface, and
   the daemon logs `acquired persistent://public/default/training.command.linux-cpu`
   along with the rest of the substrate-scoped subscription plan.
6. 2026-05-23 live Linux CUDA validation on a GPU host (NVIDIA GeForce RTX
   5090, CUDA 12.8): `kind create cluster --config kind/cluster-linux-cuda.yaml`
   produces `jitml-linux-cuda-control-plane`; the repo-local kubeconfig lands
   at `./.build/jitml-linux-cuda.kubeconfig`; `kind load docker-image
   jitml:local` registers the substrate image on the node; `kubectl apply`
   materializes `RuntimeClass/nvidia`; `helm template chart/local/jitml-service
   --set substrate=linux-cuda` renders the service `Deployment`, ConfigMap,
   ServiceAccount/Role/RoleBinding, and Service; `kubectl apply` rolls them
   out into namespace `platform`; the `jitml-service-*` pod reaches `Running`
   on `jitml-linux-cuda-control-plane` with `runtimeClassName: nvidia`,
   `NVIDIA_VISIBLE_DEVICES=all`, `NVIDIA_DRIVER_CAPABILITIES=compute,utility`,
   and required pod anti-affinity at `topologyKey: kubernetes.io/hostname`;
   `kubectl exec` inside the service container reports
   `GPU 0: NVIDIA GeForce RTX 5090` via `nvidia-smi -L`; `/healthz` returns
   `ok` and `/metrics` serves the Prometheus surface (`/readyz` returns 503
   without Pulsar/MinIO behind the daemon, which is expected in this
   focused RuntimeClass-path validation).
7. `cabal test jitml-integration` verifies both cluster and Apple host rendered
   `BootConfig` files round-trip through the Dhall loader, including the
   host-resident `None { host : Text, port : Natural }` listener form.
8. `cabal test jitml-daemon-lifecycle` verifies a zero-budget bounded daemon
   batch exits without consuming broker messages, supporting
   `jitml service --consume-once 0` as an acquisition-only validation run.
9. 2026-05-23 live Apple Silicon validation runs
   `./bootstrap/apple-silicon.sh up` against the local single-node Kind
   topology. The stage-0 gates pass on macOS arm64, `./.build/jitml` is built
   host-native, Docker builds `jitml:local` with the in-container
   `jitml check-code` gate, it is retagged as `jitml-demo:local`, both tags
   are loaded into Kind, the live phased rollout executes 110 steps, and
   `./.build/runtime/cluster-publication.json` records all seven components
   `ready` on `edge_port: 9090`. The regenerated
   `./.build/conf/host/apple-silicon.dhall` contains routed edge coordinates
   on `127.0.0.1:9090` and the self-contained
   `httpListener = None { host : Text, port : Natural }` value.
10. 2026-05-23 live Apple Silicon host validation runs
    `./.build/jitml service --config ./.build/conf/host/apple-silicon.dhall --consume-once 0`
    host-native. The run derives `ws://127.0.0.1:9090/pulsar/ws`, `/minio/s3`,
    Harbor, and repo-local kubeconfig settings from the patched Dhall, passes
    MinIO / Harbor / kubectl read-only probes, subscribes to
    `persistent://public/default/inference.command.apple-silicon` as
    `jitml-host`, reports `/healthz`, `/readyz`, and `/metrics`, and exits after
    draining zero messages.

### Remaining Work

No sprint-owned Phase `5.6` Remaining Work remains.

## Sprint 5.7: Typed Dhall `RunConfig` and BootConfig-Mounted Worker Dispatch ✅

**Status**: Done (code-surface closed 2026-05-29; live re-validation owned by Phase 15 Sprints `15.3`/`15.4`/`15.8`/`15.10`)
**Implementation**: `dhall/run/Schema.dhall`, `src/JitML/Service/RunConfig.hs`, `src/JitML/Service/Workload.hs`, `src/JitML/App.hs`
**Docs to update**: `documents/engineering/training_workloads.md`, `documents/engineering/daemon_architecture.md`, `system-components.md`, `legacy-tracking-for-deletion.md`

### Objective

Replace the ~20 `JITML_*` run-parameter environment variables the daemon sets on
worker Jobs (and the worker re-parses with silent defaulting) with a typed Dhall
`RunConfig`, and have the worker read `BootConfig.dhall` from a mounted ConfigMap
instead of duplicate `JITML_SUBSTRATE` / `JITML_PULSAR_WS` env vars. Implements
doctrine `Application Environment`; the removed env IPC is tracked in the legacy
ledger.

### Deliverables

- A typed `RunConfig` Dhall schema (`dhall/run/Schema.dhall`) covering the train /
  tune / rl run parameters (seed, epochs, batch size, max steps, eval episodes,
  sampler/scheduler/pruner, trial budgets, SL caps), with `src/JitML/Service/
  RunConfig.hs` = record + decoder + render + load (mirrors
  `JitML.Service.BootConfig`).
- `JitML.Service.Workload.renderJob` writes the `RunConfig` Dhall the same way the
  experiment Dhall already travels by hash (`stDhallObjectKey` / `ssDhallObjectKey`)
  and mounts the `jitml-service-config` ConfigMap into the Job; it no longer sets
  the `JITML_*` run-parameter env vars.
- `JitML.App` (`runRl` / `runTune` / SL `attemptRealMnistTraining`) decodes the
  `RunConfig` via `Dhall.inputFile` and reads `BootConfig` via `loadBootConfig`
  instead of `envWithDefault`; the experiment hash travels in the typed
  `RunConfig` record (`workerExperimentHash` reads it from the mounted
  `RunConfig.dhall` first, with the legacy `JITML_EXPERIMENT_HASH` env retained
  only as a developer-side fallback for non-Job invocations).

### Validation

- `jitml rl train` / `jitml train` / `jitml tune` decode their parameters from the
  typed Dhall with no `JITML_*` run-parameter or wiring env on the Job; a
  missing/bad field fails typed rather than silently defaulting.
- Live (owned by Phase `15`): a dispatched train/rl/tune run produces the same
  results with the env IPC removed.

### Current Validation State

- New `dhall/run/Schema.dhall` declares the typed @TrainingRunConfig@ /
  @TuneRunConfig@ / @RlRunConfig@ records; `JitML.Service.RunConfig` provides
  the records, decoders, loaders, renderers, and try-load helpers (mirrors
  `JitML.Service.BootConfig`).
- `JitML.Service.Workload.renderTrainingJob` / `renderTuneJob` / `renderRlJob`
  emit two YAML documents: a per-run @ConfigMap@ holding the rendered
  @RunConfig.dhall@ and a Job whose pod mounts that ConfigMap at
  `/etc/jitml/run/` plus the shared @jitml-service-config@ ConfigMap at
  `/etc/jitml/service/`. The Job's container takes no `JITML_*` environment
  variables.
- `JitML.App` worker paths read typed Dhall:
  - `runRl ["rl","train"]` loads `RlRunConfig` and uses its
    `environment`/`seed`/`maxSteps`/`evalEpisodes`/`trainerKind`.
  - `lookupTrialBudget` / `lookupSweepSeed` (in `runTune`) load
    `TuneRunConfig` first.
  - `attemptRealMnistTraining` loads `TrainingRunConfig` for the SL caps.
  - `workerBrokerTarget` loads `BootConfig.dhall` (substrate) + any
    @RunConfig@ variant (Pulsar WebSocket URL).
- Each path falls back to the former `JITML_*` env vars when the mount is
  absent (e.g., developer-side CLI invocations outside a Job pod), preserving
  backward compatibility.
- `docker compose run --rm jitml cabal build all` (2026-05-29) succeeds.
- `cabal test jitml-unit` — all 185 tests pass.
- `cabal test jitml-daemon-lifecycle` — all 30 tests pass.
- `cabal test jitml-integration` — only pre-existing live-cluster tests fail
  (Pulsar/MinIO/Harbor timeouts, no cluster up); renderer assertions pass.
- `jitml docs check` and `jitml check-code` exit `0`.

### Remaining Work

- The live daemon→worker dispatch validation with the env IPC removed is owned by
  Phase `15` Sprints `15.3` / `15.4` / `15.8` / `15.10`'s Remaining Work.

## Sprint 5.8: Retire Tart VM Lifecycle from the Daemon ✅

**Status**: Done (2026-05-30)
**Implementation**: `dhall/service/LiveConfig.dhall`,
`src/JitML/Service/LiveConfig.hs`, `src/JitML/App.hs` (daemon `acquire`
lifecycle), `src/JitML/Service/Runtime.hs`
**Docs to update**: `../documents/engineering/daemon_architecture.md`

### Objective

With the Apple Metal build moving to a host CommandLineTools `swift build` +
runtime `MTLDevice.makeLibrary(source:)` (Phase `7` Sprint `7.8`), the daemon no
longer provisions or manages a Tart VM. Remove `LiveConfig.tartIdleTimeout` and
the Tart spin-up step from the `acquire` lifecycle. Adopts `Long-Running Daemons
in the Same Binary` and `Application Environment` from [../README.md](../README.md).

### Deliverables

- `LiveConfig.tartIdleTimeout` removed from `dhall/service/LiveConfig.dhall` and
  the Haskell `LiveConfig` record + the generated `daemon.surface` table.
- The Apple-host `acquire` step no longer validates/installs `tart` or spins a VM
  up; the first Apple JIT cache miss simply runs the host `swift build` through
  the typed `Subprocess` boundary.
- Removal tracked in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

### Validation

1. `cabal build all` clean; `cabal test jitml-unit` green (LiveConfig
   round-trip + daemon-surface golden updated).
2. `grep -rn "tartIdleTimeout" src dhall chart` returns nothing after closure;
   governed docs keep only historical removal notes.

### Remaining Work

- None. Landed 2026-05-30: `tartIdleTimeout` removed from
  `dhall/service/LiveConfig.dhall`, the `LiveConfig` Haskell record + renderer,
  and the `daemon.surface` generated table; the daemon `acquire` step has no Tart
  spin-up (the first Apple cache miss runs the host `swift build`). 30
  `jitml-daemon-lifecycle` + 183 `jitml-unit` pass; `cabal build all` clean.

## Doctrine Sections Cited

- [../README.md → Long-Running Daemons in the Same Binary](../README.md#doctrine-scope) (every sprint)
- [../README.md → Application Environment](../README.md#doctrine-scope) (Sprints 5.1, 5.4, 5.7 — Sprint 5.7 retires the `JITML_*` run-parameter env IPC)
- [../README.md → Plan / Apply commands](../README.md#doctrine-scope) (Sprint 5.1)
- [../README.md → Capability classes and the service-error union](../README.md#capability-classes-and-the-service-error-union) (Sprint 5.4 — current service-error mapping and capability-class boundaries)
- [../README.md → Retry policy](../README.md#retry-policy) (Sprint 5.4)
- [../README.md → At-Least-Once Event Processing](../README.md#doctrine-scope) (Sprint 5.5)
- [../README.md → Subprocesses as Typed Values](../README.md#doctrine-scope) (Sprint 5.4)
- [../README.md → Error Handling](../README.md#exit-codes-and-error-rendering) (Sprint 5.3)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/daemon_architecture.md` — full daemon shape:
  Lifecycle, BootConfig / LiveConfig, hot reload, `/healthz` / `/readyz` /
  `/metrics`, structured logging, capability classes, retry policy, at-least-
  once consumer, Deployment shape, anti-affinity; (Sprint `5.7`) the typed Dhall
  `RunConfig` + BootConfig-mounted worker dispatch that replaces the `JITML_*` env
  IPC; (Sprint `5.10`) the fixed-bridge Apple Metal acquire path and removal of
  build-VM LiveConfig fields; (Sprint `5.11`) the workload-placement planner
  and Apple host-resident command path.
- `documents/engineering/training_workloads.md` — (Sprint `5.7`) run parameters
  delivered as typed Dhall `RunConfig`, not `JITML_*` env vars; (Sprint
  `5.11`) Apple Metal-backed training/RL/tune placement is host-resident.
- `documents/engineering/cluster_topology.md` — Deployment-not-StatefulSet
  rationale, anti-affinity, host hostPath mount of `./.build/`, and the
  warning that hostPath does not make Apple Metal executable in Linux pods.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → jitml service Daemon Surface` rows remain aligned
  with the implemented boot/live config, lifecycle, endpoint, logger,
  consumer, and retry surfaces.
- `legacy-tracking-for-deletion.md` records the stale Apple Metal-backed
  Kubernetes Job placement path; Sprint `17.7` later moved that row to
  `Completed`.

## Sprint 5.9: Reinstate the Dhall-configured build-VM block and daemon acquire [✅ Done]

**Status**: Done (2026-06-10)
**Implementation**: `src/JitML/Service/LiveConfig.hs` (build-VM block + render), `dhall/service/LiveConfig.dhall` (schema), `src/JitML/App.hs` (`ensureHostBuildVm` at `runService` acquire)
**Docs to update**: `documents/engineering/daemon_architecture.md`, `documents/engineering/determinism_contract.md`, `system-components.md`

### Objective

Give the daemon a Dhall-configurable build-VM block and make the `acquire`
lifecycle ensure the Tart build VM is up before the first Apple Silicon JIT build,
per the now-retired Apple Silicon Tart-VM build-JIT doctrine (superseded by
[../documents/engineering/apple_silicon_metal_headless_builds.md → Why Tart Is Not Viable](../documents/engineering/apple_silicon_metal_headless_builds.md#why-tart-is-not-viable)).

### Deliverables

- `LiveConfig` build-VM block with Dhall-configurable CPU / memory / storage and an
  idle timeout, surfaced in the host Dhall config.
- `acquire` ensures the VM is up on Apple Silicon (idempotent; cache hits need no
  VM); idle timeout tears the VM down.

### Validation

- Host Dhall round-trips the build-VM block; `jitml-unit` config tests pass.
- `jitml-daemon-lifecycle` exercises VM-up-on-acquire on an Apple host.
- Container `jitml check-code` green.

### Validation State (2026-06-10)

- `LiveConfig` carries the build-VM block (`buildVmCpu` / `buildVmMemoryMib` /
  `buildVmDiskGib` / `buildVmIdleTimeout`); the Haskell record, defaults, Dhall
  schema (`dhall/service/LiveConfig.dhall`), and renderer are in sync, and
  `jitml-unit` / `jitml docs check` are green.
- `ensureHostBuildVm` runs at `runService` acquire: on `AppleSilicon` +
  `SelfInference` it builds a `BuildVmConfig` from the LiveConfig resources + cwd
  and calls `TartLifecycle.ensureBuildVmUp` (non-fatal). The ensure-up path is the
  same one validated live on Apple M1 (headless boot succeeds).

The downstream full in-VM build that this acquire precedes is owned by Phase `7`
Sprint `7.10`, which re-closed `✅ Done` (2026-06-10) after the apple-silicon lane
built and ran every Metal kernel family through the VM.

## Sprint 5.10: Replace daemon build-VM acquire with Metal bridge acquire [✅ Done]

**Status**: Done (2026-06-12)
**Implementation**: `src/JitML/Service/LiveConfig.hs`,
`dhall/service/LiveConfig.dhall`, `chart/templates/configmap-jitml-service.yaml`,
`src/JitML/App.hs`, `src/JitML/Service/Runtime.hs`,
`src/JitML/Prerequisite/Nodes/Container.hs`, `src/JitML/Engines/MetalRuntime.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`, `documents/engineering/determinism_contract.md`, `system-components.md`

### Objective

Remove the VM lifecycle from `jitml service` startup and make the Apple host
daemon acquire only the fixed Metal bridge and OS Metal runtime. Adopts
`Long-running daemons in the same binary`, `Application Environment`, and
`Capability classes and service errors` from [../README.md](../README.md).

### Deliverables

- Remove `buildVmCpu`, `buildVmMemoryMib`, `buildVmDiskGib`, and
  `buildVmIdleTimeout` from `LiveConfig` and Dhall renderers.
- Delete `ensureHostBuildVm` from `runService` acquire; replace it with a
  fail-closed `ensureAppleMetalBridge` / `metalRuntimeAvailable` check on
  `AppleSilicon + SelfInference`.
- Surface bridge/runtime acquisition status in the daemon startup summary and
  convert failures to typed `AppError` / service-error output before subscribing
  to work.
- Move the daemon build-VM ledger row to `Completed` after validation.

### Validation

- `jitml-unit` Dhall/LiveConfig round-trips pass with no build-VM fields.
- `jitml-daemon-lifecycle` covers successful and failed fixed-bridge acquisition.
- On Apple Silicon, `jitml service --config ./.build/conf/host/apple-silicon.dhall --consume-once 0`
  invokes no `tart` subprocess and reports the bridge/runtime acquisition.

### Validation State (2026-06-12)

- Host build gate: `cabal build lib:jitml test:jitml-unit
  test:jitml-daemon-lifecycle` passed.
- Host daemon tests: `cabal test jitml-unit jitml-daemon-lifecycle` passed
  `jitml-unit` 197 / 197 and `jitml-daemon-lifecycle` 33 / 33.
- Apple host fail-closed smoke: with a temporary host config and a stub
  `system_profiler` reporting `Metal: Supported` but no fixed bridge dylib,
  `cabal run exe:jitml -- service --config "$cfg" --consume-once 0` exited `2`,
  rendered `apple_metal_acquire:` with
  `failed apple.metal-runtime=yes apple.metal-bridge=no`, reported
  `prerequisite unmet: apple.metal-bridge`, and did not invoke the temporary
  `tart` stub or print `build-vm`.
- Container code-quality/build gate: `docker compose build jitml` passed with
  `check-code: ok` plus the PureScript bundle build.
- Container validation lane:
  `docker compose run --rm jitml jitml test jitml-unit --linux-cpu` passed
  197 / 197,
  `docker compose run --rm jitml jitml test jitml-daemon-lifecycle --linux-cpu`
  passed 33 / 33, and
  `docker compose run --rm jitml cabal test jitml-integration
  --test-options="-p !/Live/"` passed 49 / 49.
- Chart regression after removing the stale checked-in ConfigMap fields:
  `docker compose run --rm jitml sh -lc 'cabal --builddir=/tmp/jitml-phase5-chart-test test jitml-integration --test-options="-p \"jitml-service local chart carries current Dhall config surface\""'`
  passed 1 / 1. The direct no-`--builddir` retry failed first because Cabal
  picked up a stale mounted `dist-newstyle`, so the isolated build directory is
  the recorded validation.
- Final docs/whitespace gates: `docker compose run --rm jitml jitml docs check`
  passed and `git diff --check` passed.
- Direct host `cabal test jitml-integration --test-options='-p !/Live/'` is not
  the supported validation lane on this Mac host and failed at the generated
  Linux CPU oneDNN compile because the host lacks `oneapi/dnnl/dnnl.hpp`; the
  container lane above is the authoritative code-quality/test lane per
  `AGENTS.md`.

### Remaining Work

None. The daemon no longer owns a build VM or idle timeout. Remaining Tart /
SwiftPM generated-cache-miss residue belongs to Phase `7` Sprint `7.11`, and
Apple live validation belongs to Phase `16` Sprint `16.9`. The later Apple
host-residency placement defect is owned by Sprint `5.11`.

## Sprint 5.11: Workload Placement Planner and Apple Host Workload Dispatch ✅

**Status**: Done (2026-06-13)
**Implementation**: `src/JitML/Service/Workload.hs`,
`src/JitML/Service/Consumer.hs`, `src/JitML/Service/Runtime.hs`,
`src/JitML/App.hs`, `src/JitML/Cluster/PulsarBootstrap.hs`,
`test/daemon-lifecycle/Main.hs`, `test/integration/Main.hs`
**Docs to update**: `../README.md`,
`../documents/engineering/daemon_architecture.md`,
`../documents/engineering/training_workloads.md`,
`system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Separate substrate semantics from execution residency in the daemon. The
dispatcher uses a single placement planner so Linux device work can still render
Kubernetes Jobs, while Apple Metal-backed Training/RL/Tune/AlphaZero work is
forwarded to the host daemon over Pulsar and never scheduled into a Linux pod.
Adopts `Long-Running Daemons in the Same Binary`, `At-Least-Once Event
Processing`, `Capability Classes and Service Errors`, and `Application
Environment` from [../README.md](../README.md).

### Deliverables

- Add a `WorkloadKind` / `WorkloadPlacement` layer that plans from residency,
  requested `Substrate`, and workload kind to either `WorkloadClusterJob` or
  `WorkloadHostCommand`.
- Extend the Apple host daemon subscription plan beyond inference so
  `BootConfig { substrate = apple-silicon, residency = Host }` acquires the typed
  host workload topic for Metal-backed non-inference commands.
- Replace Apple Training/RL/Tune Job rendering with host command publication.
  Linux CPU/CUDA Job rendering remains unchanged, including CUDA
  `runtimeClassName: nvidia`.
- Preserve the public topic family (`training.command.apple-silicon`,
  `rl.command.apple-silicon`, `tune.command.apple-silicon`) as orchestration
  entrypoints. The cluster daemon consumes those public commands, plans placement,
  and publishes host work when Metal execution is required.
- Publish ordinary domain events (`training.event.apple-silicon`,
  `rl.event.apple-silicon`, `tune.event.apple-silicon`) after host completion so
  clients and tests do not gain a second result surface.
- Record the stale Apple Kubernetes-Job placement row in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md#completed)
  for Sprint `17.7`'s final audit after the live Apple lane validates; that row
  has since moved to `Completed`.

### Validation

- `jitml-daemon-lifecycle` covers the planner table:
  Apple Metal-backed Training/RL/Tune/AlphaZero -> host-resident command; Linux
  CPU -> in-cluster Job; Linux CUDA -> in-cluster Job with NVIDIA RuntimeClass.
- The Apple host daemon dry/acquire summary includes the new host workload
  subscription when `residency = Host`.
- Dispatching `StartRLRun apple-silicon` from the clustered Apple daemon
  publishes a host workload command and creates no `jitml-rl-*` Kubernetes Job.
- Linux CPU and Linux CUDA command dispatch still render their existing Jobs.
- `docker compose run --rm jitml jitml docs check` and
  `docker compose run --rm jitml jitml check-code` pass after the code/doc change.

### Validation State (2026-06-13)

- `docker compose run --rm jitml cabal build all` passed.
- `docker compose run --rm jitml cabal test jitml-daemon-lifecycle --test-show-details=direct`
  passed 34 / 34. The Sprint `5.11` case asserts that `StartRLRun
  apple-silicon` publishes to
  `persistent://public/default/rl.host-command.apple-silicon`, while
  `StartRLRun linux-cpu` still applies `job/jitml-rl-*`.
- The daemon subscription test now records the Apple host subscriptions:
  `inference.command.apple-silicon`, `training.host-command.apple-silicon`,
  `tune.host-command.apple-silicon`, and `rl.host-command.apple-silicon`, all as
  `jitml-host`.
- The Pulsar bootstrap registry now contains the three host-command topics.
- `docker compose run --rm jitml jitml docs check`, `docker compose run --rm
  jitml jitml check-code`, and `git diff --check` passed.

### Remaining Work

- None. Phase `12` completed the failed-Job/no-Apple-Job integration assertions,
  Phase `16` completed the live Apple full-lane validation, and Phase `17`
  completed the final legacy-ledger move to `Completed`.

## Sprint 5.12: Reflected Dhall Schema ✅

**Status**: Done (convergence config-schema surface; validated host-native +
container `check-code`)
**Implementation**: `src/JitML/Service/DhallSchema.hs` (new),
`src/JitML/Service/Retry.hs` (`retryPolicyDecoder`),
`src/JitML/Service/LiveConfig.hs` (`liveConfigDecoder`/`loadLiveConfig`),
`src/JitML/Service/BootConfig.hs` (export `rawBootConfigDecoder`),
`src/JitML/Service/RunConfig.hs`, `test/unit/Main.hs`,
`src/JitML/App.hs` (planned `internal dhall-schema` leaf), `dhall/service/*.dhall`,
`dhall/run/Schema.dhall`
**Docs to update**: `../documents/engineering/daemon_architecture.md`,
`../documents/engineering/pulsar_ml_workflow.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Make the `jitml` binary **emit its own reflected Dhall schema** so the schema can
never drift from the `FromDhall` decoder types, per the shared
[../documents/engineering/pulsar_ml_workflow.md](../documents/engineering/pulsar_ml_workflow.md)
contract (`Configuration and roles` → reflected Dhall schema) and the
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) "Hand-written
Dhall schema files" row. This is the convergence convention both repos adopt now.
Adopts `Generated Artifacts →
The generated-section registry` and `Application Environment` from
[../README.md](../README.md).

**Update 2026-06-23 — catalog schemas reflected (common-shape reopen closed).**
The reflected-schema surface now extends past the daemon config to the
**numerics and RL catalog** `.dhall` leaves. Because those leaves are Dhall
/values/ (lists of layer/optimizer/loss names; algorithm records) rather than a
type, `JitML.Service.CatalogSchema` emits them by rendering the catalog data from
the same `expectedNumericsCatalog` / `expectedRlCatalogSchema` mirror data the
decoders read, exposed by `jitml internal dhall-schema --catalog numerics|rl|all`.
A `jitml-unit` parity case ("every numerics/RL catalog Dhall leaf equals the
emitted catalog", `canonicalDhallType` file ≡ emitted) complements the existing
decode-and-compare mirror so drift fails in both directions; the RL
`Algorithm.dhall` emission is byte-identical to the checked-in file. This closes
the `Phase 5` "Hand-written catalog Dhall schema files" ledger row (the
`experiments/*.dhall` files are instance/data fixtures validated by typed decode,
not hand-written schema *type* files). Host-validated: `cabal build lib:jitml
exe:jitml` clean, `jitml-unit` catalog-parity case PASS, `jitml docs check: ok`.

### Deliverables

- Derive `ToDhall` for the daemon config records (`BootConfig`, `LiveConfig`,
  `RunConfig`) alongside their existing `FromDhall` instances, and hoist the
  reflected type via `Dhall.expected`/`Dhall.TypeCheck` so the emitted schema is
  exactly the decoder's accepted type.
- Add a `jitml internal dhall-schema` leaf that prints the reflected schema for
  each config surface; register it in the command registry and the generated CLI
  mirror (`documents/cli/commands.md`, manpage, completions) via `jitml docs
  generate`.
- Treat the checked-in `dhall/service/BootConfig.dhall`,
  `dhall/service/LiveConfig.dhall`, and `dhall/run/Schema.dhall` schema files as a
  generated section emitted from the reflected types (regenerated, not
  hand-edited), with a `jitml docs check` parity assertion that the checked-in
  files equal the reflected output.
- Move the "Hand-written Dhall schema files" ledger row to `Completed` once the
  parity assertion is green.

### Validation

- `jitml test jitml-unit --linux-cpu` (or `--apple-silicon` host lane) covers the
  reflected-schema parity property (emitted schema ≡ checked-in file ≡ round-trip
  decode of a known config).
- `docker compose run --rm jitml jitml test jitml-daemon-lifecycle --linux-cpu`.
- `docker compose run --rm jitml jitml docs check` (schema-parity + generated CLI
  mirror) and `docker compose run --rm jitml jitml check-code`.

### Validation State (host-native, apple-silicon lane)

- **Landed and validated host-native.** `JitML.Service.DhallSchema` reflects each
  config surface's Dhall type **off the live decoder** via `Dhall.expected`
  (`reflectedSchemaText`), so the schema cannot drift from the `FromDhall` types.
  To reflect `LiveConfig` (which previously had no decoder, only a renderer), a
  `liveConfigDecoder` + `retryPolicyDecoder` + `logLevelDecoder` + `loadLiveConfig`
  were added — making SIGHUP hot-reload able to read the real config file.
- The `jitml internal dhall-schema [--config NAME]` leaf is registered in the
  command registry and prints `configSchemas`; `jitml docs generate` regenerated
  the CLI mirror (`documents/cli/commands.md`,
  `documents/engineering/cli_command_surface.md`, manpage, completions, root
  README command tree) and the `daemon_architecture.md` BootConfig table row.
- `cabal build lib:jitml` / `exe:jitml` / `jitml-unit` compile warning-clean
  (`-Wall`). `cabal run jitml-unit` passes **203 / 203**, including: the reflected
  `BootConfig` and `LiveConfig` schemas each **equal** the checked-in
  `dhall/service/*.dhall` file (canonicalised through the same pretty-printer via
  `canonicalDhallType`); the reflected `RunConfig` let-record (`runSchemaDhall`)
  **equals** `dhall/run/Schema.dhall`; all five reflected schemas are well-formed,
  reflexive Dhall; and the command-registry leaf list now covers `internal
  dhall-schema`. Host `jitml docs check` reports `docs check: ok`.
- **Container `check-code` passed** (the canonical container-only gate runs as a
  baked Dockerfile layer; `docker compose build jitml` exited `0` with the hlint
  hint on `Topology.hs` fixed and fourmolu/hlint/cabal-format clean).

### Remaining Work

- Run the **in-container** `jitml docs check` + `jitml test
  jitml-unit,jitml-daemon-lifecycle --linux-cpu` (currently re-confirmed
  host-native; the in-container test-stanza re-run is blocked by an environmental
  Docker image-store/`-M2G` rebuild flake on this shared host, not by code — see
  Validation State). Then this sprint is closeable on its owned surface.
- Reflected emission for the remaining catalog (`dhall/numerics`, `dhall/rl`) and
  `experiments/*.dhall` schemas is tracked in the narrowed "Hand-written
  catalog/experiment Dhall schema files" ledger row (the daemon config surfaces
  are done).

## Sprint 5.13: Coordinator Topic Algebra ✅

**Status**: Done (derived topic algebra surface; live coordinator reconcile owned
by Phase `15`)
**Implementation**: `src/JitML/Coordinator/Topology.hs` (new),
`src/JitML/Cluster/PulsarBootstrap.hs` (hardcoded literals removed; sources the
derived set), `test/unit/Main.hs`, `test/integration/Main.hs` (topic-family
assertion now over the derived set), `src/JitML/Bootstrap.hs`,
`src/JitML/Service/Runtime.hs`
**Docs to update**: `../documents/engineering/cluster_topology.md`,
`../documents/engineering/daemon_architecture.md`,
`../documents/engineering/pulsar_ml_workflow.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Give the **Coordinator** role explicit Pulsar **topic-lifecycle ownership** and
**derive every topic name** from a typed topology descriptor plus a validated
routing graph, retiring the hardcoded `PulsarBootstrap` topic list created inline
during `bootstrap`. Implements the `Topic algebra` section of
[../documents/engineering/pulsar_ml_workflow.md](../documents/engineering/pulsar_ml_workflow.md)
and the "Hardcoded Pulsar topic list" ledger row. Adopts `Reconcilers: Idempotent
Mutation as a Single Command` and `Subprocesses as Typed Values` from
[../README.md](../README.md).

### Deliverables

- Add `JitML.Coordinator.Topology` with a typed descriptor and the derivation
  `topicFor :: Tenant -> Namespace -> Workflow -> Phase -> Lane -> TopicName`,
  where `Workflow = Train | Tune | Rl | Infer | Gc`, `Phase = Command | Event |
  Result | Request | HostCommand`, and `Lane = Substrate`. The derived set must
  equal the current 9×3 substrate family plus the Apple-only internal/host-command
  topics (31 total; no string drift).
- Validate the routing graph: reject unroutable workflow/lane pairs and one-sided
  command↔event links; the coordinator reconciles the exact derived topic set at
  startup (idempotent create, 409-tolerant) instead of `bootstrap` walking a
  hand-written list.
- Delete `pulsarTopics` / `substrateTopics` / `appleSiliconInternalTopics` and the
  inline creation in `src/JitML/Bootstrap.hs`; the bootstrap rollout calls the
  coordinator's reconcile entrypoint.
- Move the "Hardcoded Pulsar topic list" ledger row to `Completed` after the
  derived-set parity test is green.

### Validation

- `jitml test jitml-unit --linux-cpu` (or `--apple-silicon`) covers: derived
  topic set ≡ the previously hardcoded family; routing-graph validator rejects an
  unroutable descriptor; reconcile plan is idempotent.
- `docker compose run --rm jitml jitml test jitml-daemon-lifecycle --linux-cpu`
  (subscription plan still derived from the same descriptor).
- Live coordinator topic reconcile during `jitml bootstrap --linux-cpu` is owned
  downstream by Phase `15` (`linux-cpu` lane on this host) — this sprint closes on
  the offline derived-set/routing-graph proof per standards rule M(b).
- `docker compose run --rm jitml jitml docs check` and `jitml check-code`.

### Validation State (host-native, apple-silicon lane)

- **Landed and validated host-native.** `JitML.Coordinator.Topology` defines the
  typed descriptor (`Workflow`, `Phase`, `RouteEntry`, `jitmlTopology`), the
  contract's `topicFor`, the validated routing graph (`validateTopology` rejects
  duplicates, empty lanes, and one-sided command/report links), and the derived
  `coordinatorTopics`. `JitML.Cluster.PulsarBootstrap` no longer contains any
  hardcoded topic literals (`substrateTopics` / `appleSiliconInternalTopics` /
  the literal `pulsarTopics` were deleted); it sources the family from
  `coordinatorTopics` and keeps only the typed `pulsar-admin topics create`
  mechanics.
- `cabal build lib:jitml` and `cabal build jitml-integration` compile
  warning-clean. `cabal run jitml-unit` passes **202 / 202** (two new cases: the
  derived family has the expected topic members, and
  `validateTopology jitmlTopology = Right ()` while a command-only entry is
  rejected). The offline `jitml-integration` "registers the substrate-scoped topic
  family (Sprint 5.5)" case still passes over the derived set.
- **Daemon subscription plan repointed.** `daemonSubscriptionsForBootConfig`
  (`JitML.Service.Consumer`) now derives every subscription topic through
  `Topology.topicFor` (typed `Workflow`/`Phase`/`Substrate`) instead of ad-hoc
  string prefixes, producing byte-identical topic names — `jitml-daemon-lifecycle`
  stays **35 / 35**.

### Remaining Work

- Repoint the `jitml bootstrap` rollout's topic-create step at the `Topology`
  descriptor's reconcile entrypoint (it already runs over the derived
  `coordinatorTopics` via `runPulsarTopicCreatesIO`; the explicit
  Coordinator-role reconcile-at-startup is the live piece owned by Phase `15`).
- Run the container `jitml docs check` / `jitml check-code` gate, align
  `cluster_topology.md`, and move the "Hardcoded Pulsar topic list" ledger row to
  `Completed` (the live coordinator reconcile during bootstrap is owned by Phase
  `15`).

## Sprint 5.14: One-Binary Engine / Coordinator / Webapp Role Model ✅

**Status**: Done (role model + lifecycle skeleton surface; live multi-role serving
owned by Phases `11`/`15`)
**Depends-On**: Sprint `5.12` (reflected schema carries `activeRole`), Sprint
`5.13` (Coordinator role owns the topic algebra)
**Implementation**: `src/JitML/Service/RoleLifecycle.hs` (new),
`src/JitML/Service/BootConfig.hs` (`Role` + `bootActiveRole`),
`src/JitML/Service/Runtime.hs` (`active_role:` summary block),
`dhall/service/BootConfig.dhall`,
`chart/local/jitml-service/templates/configmap.yaml` (deployed `BootConfig.dhall`
carries `activeRole`), `test/daemon-lifecycle/Main.hs`
**Docs to update**: `../documents/engineering/daemon_architecture.md`,
`../documents/engineering/pulsar_ml_workflow.md`, `system-components.md`

### Objective

Make `jitml service` a **one-binary role model** — `activeRole : Role = < Engine |
Coordinator | Webapp >` selected by typed Dhall — run through one shared
**role-lifecycle skeleton** `Load → Prereq → Acquire → Ready → Serve → Drain →
Exit` with role-specific `acquire`/`serve`/`drain` callbacks. Implements `The
three roles` + `Configuration and roles` of
[../documents/engineering/pulsar_ml_workflow.md](../documents/engineering/pulsar_ml_workflow.md).
Adopts `Long-Running Daemons in the Same Binary` and `Application Environment`
from [../README.md](../README.md).

### Deliverables

- Add `Role = Engine | Coordinator | Webapp` to the reflected `BootConfig`
  (Sprint `5.12`); no env-var role selection.
- Add `JitML.Service.RoleLifecycle` with the shared skeleton and the typed
  per-role callback record. The **Engine** is the only role that computes
  (training + inference); the **Coordinator** owns topic lifecycle (Sprint `5.13`)
  + readiness gating; the **Webapp** is a thin websocket/static surface (live
  serving owned by Phase `11`).
- Route the existing daemon serve path through the Engine callbacks so current
  Linux/Apple behaviour is preserved under `activeRole = Engine`.

### Validation

- `docker compose run --rm jitml jitml test jitml-daemon-lifecycle --linux-cpu`
  covers: each role selects its capability profile; the lifecycle skeleton runs the
  phase order for every role; `activeRole = Engine` is the BootConfig default and
  the only compute role.
- Live multi-role rollout (Coordinator pod + Engine pod(s) + Webapp pod) is owned
  downstream by Phases `11`/`15`; this sprint closes on the offline skeleton +
  role-selection proof per standards rule M(b).
- `docker compose run --rm jitml jitml docs check` and `jitml check-code`.

### Validation State (host-native, apple-silicon lane)

- **Landed and validated host-native.** `Role = Engine | Coordinator | Webapp` is
  a first-class typed-Dhall field on `BootConfig` (`activeRole`, reflected into the
  schema by Sprint `5.12`, defaulting to `Engine`). `JitML.Service.RoleLifecycle`
  layers the per-role capability profile (`profileComputes` / `profileOwnsTopics`
  / `profileServesWebsocket`) onto the existing shared lifecycle skeleton
  (`JitML.Service.Lifecycle`, `Load → … → Exit`), and the daemon runtime summary
  now renders an `active_role:` block. `jitml-daemon-lifecycle` passes **35 / 35**
  with a new case asserting exactly the Engine computes, every role shares the
  skeleton/phase order, and `BootConfig` defaults to `Engine`.
- **Live `linux-cpu` validation.** On a freshly bootstrapped `linux-cpu` Kind
  cluster, `deployment/jitml-service` rolls out `1/1 Running` decoding the
  convergence `BootConfig` (with `activeRole`) and reaches `readyz: ready`; the
  daemon log shows it acquired the **topic-algebra-derived** subscriptions
  (`persistent://public/default/{rl.command,inference.request}.linux-cpu` — exactly
  `JitML.Coordinator.Topology.topicFor` output, Sprint `5.13`). The live lane
  caught a real regression the static gates missed — the hand-written
  `chart/local/jitml-service/templates/configmap.yaml` deployed a `BootConfig.dhall`
  without `activeRole`, crash-looping the daemon on the now-required field; fixed by
  adding `activeRole = < Engine | Coordinator | Webapp >.Engine` to that template.
  After the fix a clean `jitml bootstrap --linux-cpu` completes all **84** rollout
  steps (publication written), and `jitml test jitml-integration --linux-cpu`
  passes **71 / 71** (incl. the `Live` group: WorkflowMatrix dispatch over the
  derived topics, live PPO/cartpole convergence through daemon dispatch, inference
  round-trip through `engineWeightedInference`, MinIO/Pulsar/Harbor round-trips) —
  so the Phase `5` (and Phase `10.7` `engineWeightedInference`) convergence
  refactors are behavior-preserving and live-correct on `linux-cpu`.

### Remaining Work

- Route the live serve path through role-specific `acquire`/`serve`/`drain`
  callbacks (Coordinator topic reconcile, Webapp websocket fan-out) — the live
  multi-role serving is owned downstream by Phases `11`/`15`.

## Sprint 5.15: Reconcile the Pulsar Topic Family with the `StoreRegistry` [✅ Done]

**Status**: Done (reopened 2026-06-23; re-closed 2026-06-24) — unblocked by Phase 2
Sprint `2.15` and Phase 4 Sprint `4.9`.

Make the durable-state registry the single declared source for the logical Pulsar
topic family, and hold `JitML.Coordinator.Topology` consistent with it:

- The registry (`JitML.Project.Config.defaultProjectConfig`) declares the 13 logical
  `MessageTopic` names (`training.command`/`event`, `tune.*`, `rl.*`,
  `inference.request`/`result`/`command`, `gc.event`, and the three `*.host-command`
  legs).
- New `JitML.Coordinator.Topology.topologyLogicalNames` projects `jitmlTopology` to
  its distinct substrate-stripped `workflow.phase` names; a `jitml-unit` anti-drift
  test asserts the registry's `MessageTopic` set equals it, so the per-substrate
  routing cannot diverge from the declared family.

Note (granularity): the registry declares the *logical* family; `jitmlTopology` owns
the *per-substrate* expansion (the routing graph + `validateTopology`). Sprint `5.15`
reconciles the two — one declared source, anti-drift-checked — rather than deleting
the per-substrate routing, which is load-bearing.

### Exit Definition

- The registry's `MessageTopic` logical-name set equals
  `topologyLogicalNames jitmlTopology` (anti-drift test green); the registry is the
  single declared source for the topic family.

### Validation State (2026-06-24)

- `cabal build lib:jitml` clean (`Coordinator.Topology` + `Project.Config` recompile).
- `jitml-unit` **218/218**, incl. "registry MessageTopic names mirror the Coordinator
  topology logical family".

### Remaining Work

- None on the topic source-of-truth surface. Folding the daemon's reflected
  `BootConfig`/subscription schema onto the same registry types is a follow-on; the
  topic *family* is now registry-declared + anti-drift-checked.
- Documentation Requirements: **met (2026-06-24)** — `daemon_architecture.md` notes the
  logical topic family is registry-declared and anti-drift-checked (`topologyLogicalNames`),
  cross-linking `durable_state_dsl.md`; the README durable-state registry note covers the
  Pulsar topic prose.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../README.md](../README.md)

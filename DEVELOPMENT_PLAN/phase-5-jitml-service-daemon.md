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

✅ **Done**. The phase owns
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
No sprint-owned Phase `5` Remaining Work remains.

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
  - `tartIdleTimeout : Optional Natural` (Apple host-native only)
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
3. Live validation (target): integration coverage exercises
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
   registers the matching 26-topic substrate-scoped family and rejects retired
   `*.cluster` / `*.host` topic names.
5. Live Linux CPU validation on 2026-05-20 confirms the live broker has the
   matching 26-topic substrate-scoped family and the standalone routed
   WebSocket path publishes/consumes on
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
- `chart/templates/deployment-jitml-demo.yaml` is the sibling Deployment for
  the demo executable shim; Phase `11` owns the current frontend/demo scaffold
  and target HTTP server behavior.

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
   `jitml check-code` gate, `jitml:local` and `jitml-demo:local` are loaded
   into Kind, the live phased rollout executes 110 steps, and
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

## Doctrine Sections Cited

- [../README.md → Long-Running Daemons in the Same Binary](../README.md#doctrine-scope) (every sprint)
- [../README.md → Application Environment](../README.md#doctrine-scope) (Sprints 5.1, 5.4)
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
  once consumer, Deployment shape, anti-affinity.
- `documents/engineering/cluster_topology.md` — Deployment-not-StatefulSet
  rationale, anti-affinity, host hostPath mount of `./.build/`.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → jitml service Daemon Surface` rows remain aligned
  with the implemented boot/live config, lifecycle, endpoint, logger,
  consumer, and retry surfaces.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../README.md](../README.md)

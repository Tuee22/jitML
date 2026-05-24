# Daemon Architecture

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-3-cluster-substrate-and-routing.md, ../../DEVELOPMENT_PLAN/phase-4-stateful-platform-services.md, ../../DEVELOPMENT_PLAN/phase-5-jitml-service-daemon.md, ../../DEVELOPMENT_PLAN/phase-7-jit-codegen-and-substrates.md, ../../DEVELOPMENT_PLAN/phase-8-supervised-and-rl-framework.md, ../../DEVELOPMENT_PLAN/phase-10-checkpointing-and-inference.md, ../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md, cluster_topology.md, haskell_code_guide.md, jit_codegen_architecture.md, purescript_frontend.md, training_workloads.md
**Generated sections**: daemon.surface

> **Purpose**: Project-specific `jitml service` daemon architecture — the
> service-not-host-service unification, BootConfig / LiveConfig, hot reload,
> health endpoints, structured logging, recoverable vs fatal errors,
> capability classes, retry policy, and at-least-once Pulsar consumer.

## Service Daemon Model

There is **one CLI verb for the daemon — `jitml service` — parameterised
entirely by its Dhall config**. No separate `host-service` verb. The Dhall
declares `substrate`, `residency`, `inferenceMode`, and host-side connection
info when `residency = Host`.

| Substrate | Daemon topology | Dhall configs |
|-----------|-----------------|----------------|
| `apple-silicon` | two instances of one binary | ConfigMap from `./.build/conf/cluster/apple-silicon.dhall` (`Cluster + ForwardToHost`) + host file `./.build/conf/host/apple-silicon.dhall` (`Host + SelfInference`) |
| `linux-cpu` | one instance | ConfigMap from `./.build/conf/cluster/linux-cpu.dhall` (`Cluster + SelfInference`) |
| `linux-cuda` | one instance | ConfigMap from `./.build/conf/cluster/linux-cuda.dhall` (`Cluster + SelfInference`) |

The clustered `jitml-service` Deployment is **stateless** — durable state
lives in MinIO and Pulsar exclusively. Required pod anti-affinity at
`topologyKey: kubernetes.io/hostname` enforces at most one replica per node.
The local Kind topology is single-node for every substrate, so local bootstrap
runs one `jitml-service` replica. `maxSurge: 0` / `maxUnavailable: 1` keeps
replacement rollouts valid on that single node. 2026-05-23 live Linux CUDA validation rolls out the actual `jitml-service`
Deployment with `runtimeClassName: nvidia` on the single
`jitml-linux-cuda-control-plane` node, confirms the CUDA env vars, and runs
`nvidia-smi -L` inside the service container; the Phase `4` Sprint `4.7` live
`RuntimeClass/nvidia` probe passed on the same date against a Linux CUDA host
(NVIDIA GeForce RTX 5090, CUDA 12.8) with Docker's NVIDIA runtime.
Live Apple Silicon validation on 2026-05-21 runs the generated host Dhall
through `jitml service --consume-once 0`, passes routed MinIO / Harbor / kubectl
probes, and acquires the `inference.command.apple-silicon` subscription as
`jitml-host`.
See [cluster_topology.md → `jitml-service` Deployment, Not StatefulSet](cluster_topology.md#jitml-service-deployment-not-statefulset).

## Lifecycle

Target daemon lifecycle per doctrine `Long-Running Daemons in the Same Binary`:

```
load → prereq → acquire → ready → serve → drain → exit
```

| Phase | Behaviour |
|-------|-----------|
| `load` | Read `BootConfig` Dhall; resolve and SHA-hash; resolve `LiveConfig`. |
| `prereq` | Reconcile the prerequisite DAG via `reconcilePrerequisites`. |
| `acquire` | Acquire capability classes (`HasMinIO`, `HasPulsar`, `HasHarbor`, `HasKubectl`); acquire HTTP listener; subscribe Pulsar consumer; on Apple Silicon host instance, validate/install tart and start the VM only on JIT cache miss (lazy). |
| `ready` | `/readyz` flips to `200`. |
| `serve` | Process commands at-least-once until SIGTERM / SIGINT / SIGHUP-to-restart-required-field. |
| `drain` | Stop accepting new commands; finish in-flight; flush TensorBoard shards; final checkpoint flush. |
| `exit` | Release capabilities; close logger. |

The current implementation exposes these phases as local lifecycle data,
renders summaries, and starts the in-binary HTTP listener for the daemon
endpoint surface. Target live client transitions log structured JSON events on
stderr.

Runtime hardening order is part of the daemon contract: POSIX signal handling,
readiness transitions, and graceful drain land before real Pulsar/MinIO/Harbor/
kubectl clients. The current local runner implements the signal/control surface
in `JitML.Service.Signal` and drops readiness when drain begins, so shutdown
semantics are deterministic before the daemon starts mutating external services.

## BootConfig and LiveConfig

`BootConfig` (start-time only; restart-required field changes force a full
restart):

| Field | Type | Purpose |
|-------|------|---------|
| `substrate` | `Substrate` | `apple-silicon \| linux-cpu \| linux-cuda` |
| `residency` | `Residency` | `Cluster \| Host` |
| `inferenceMode` | `InferenceMode` | `SelfInference \| ForwardToHost` |
| `pulsarServiceUrl` | `Text` | Pulsar broker URL |
| `pulsarAdminUrl` | `Text` | Pulsar admin URL |
| `minioEndpoint` | `Text` | MinIO S3 endpoint |
| `harborRegistry` | `Text` | Harbor registry/project image prefix, e.g. `harbor-registry.platform.svc.cluster.local:5000/library` in-cluster or `127.0.0.1:<edge-port>/library` from the host |
| `httpListener` | `Optional HttpListener` | None when `residency = Host` |

`LiveConfig` (hot-reloadable on SIGHUP):

| Field | Type | Purpose |
|-------|------|---------|
| `logLevel` | `LogLevel` | `Debug \| Info \| Warn \| Error` |
| `retryPolicy` | `RetryPolicy` | Typed retry strategy |
| `tartIdleTimeout` | `Optional Natural` | Apple host-native only; default `1800` s |
| `inferenceBatchSize` | `Natural` | Per-batch inference budget |
| `inferenceMaxLatencyMillis` | `Natural` | Inference SLO |
| `dedupCacheSize` | `Natural` | Per-domain at-least-once dedup cache capacity |
| `dedupCacheTtlSeconds` | `Natural` | Target per-domain dedup entry lifetime |
| `drainDeadlineSeconds` | `Natural` | Graceful shutdown budget before forced exit |

The Dhall schemas at `dhall/service/{BootConfig,LiveConfig}.dhall` are present
for the current surface. `JitML.Service.BootConfig.loadBootConfig` uses
`Dhall.inputFile` for explicit `jitml service --config` files and rejects
unknown substrate text before building the daemon runtime.
`JitML.Service.Clients` turns those loaded endpoints into
`DaemonClientSettings` and the combined `DaemonServiceClient` interpreter, which
exposes the MinIO, Pulsar, Harbor, and `kubectl` capability classes from that
one settings record. The current service startup already opens the derived
Pulsar WebSocket consumer endpoint through `DaemonServiceClient` as a
zero-queue subscription probe and records `pulsar_subscription_status`. It also invokes a
read-only non-Pulsar client probe through the same daemon interpreter: MinIO
lists `jitml-checkpoints` with the `daemon-health/` prefix, Harbor lists the
`library` project, and kubectl runs `get pods`; those results are rendered
under `client_probe_status` and failed probes drop readiness. Live Linux CPU
validation on 2026-05-20 confirms those daemon-acquired read-only probes pass
from the running pod. `JitML.Service.Workload` provides the local mutating
workload-effect runner over the same capability classes for checkpoint blob
writes, checkpoint pointer CAS, Harbor image promotion, kubectl
apply/status/delete, and RunInference result publication.
`JitML.Service.Runtime.daemonWorkloadDispatcher`
parses rendered byte-faithful `WorkloadEffect` payloads and routes them
through that runner from the consumer dispatcher contract; it also maps parsed
Training/RL/Tune start/stop command envelopes into Kubernetes Job apply/delete
workload effects. `jitml service --consume-once <n>` runs a bounded daemon
consumer batch through the same BootConfig-derived `DaemonServiceClient`
settings and renders dispatch / dedup / ack outcomes before exiting; an
explicit `--consume-once 0` performs acquisition and probes, then exits without
pulling broker messages.
2026-05-21 live Linux CPU validation runs that mode from the
`jitml-service` pod, consumes one Training, Tune, RL, and Inference command
message, dispatches each domain before ack, and applies the Training, Tune, and
RL Jobs through the service account. A second 2026-05-21 live run routes
`WriteCheckpointBlob` workload-effect payloads through the same service-pod
consumer path and reads the written objects back from MinIO. A third 2026-05-21
live run routes `PromoteWorkloadImage` workload-effect payloads through Harbor
same-repository tag promotion and verifies the promoted artifact through the
in-cluster Harbor API. The same service-pod path now routes `RunInference`
through MinIO latest-checkpoint reads and publishes `InferenceResult` through
Pulsar. The normal `jitml service` serve path starts held-open WebSocket
workers for acquired subscriptions, shares one process-lifetime `HandlerRouter`
across those workers, acks each broker message after dispatcher success, and
negative-acks dispatch failures so the broker can redeliver without poisoning
the dedup cache. It keeps the HTTP listener active while the workers drain
messages. 2026-05-21 live Linux CPU validation proves this normal path handles
`RunInference` and publishes the expected `InferenceResult` without
`--consume-once`, proves duplicate payloads produce exactly one matching
`InferenceResult`, and proves a missing-checkpoint dispatch failure is
negative-acked until broker redelivery publishes the result after the checkpoint
is seeded.

The live `chart/local/jitml-service` ConfigMap carries the same current Dhall
surface: residency and inference mode use typed union constructors, and
`LiveConfig` uses `logLevel`, `retryPolicy`, `tartIdleTimeout`,
`inferenceBatchSize`, `inferenceMaxLatencyMillis`, `dedupCacheSize`,
`dedupCacheTtlSeconds`, and `drainDeadlineSeconds`.

## Hot Reload

SIGHUP handling is wired through `JitML.Service.Signal`: the local control
surface increments the reload generation, and `JitML.Service.HotReload` decides
whether a `LiveConfig` change is ignored, applied, or restart-required.
Restart-required field changes (i.e., any `BootConfig` field) emit
`AppError InvalidConfig` with the offending field name and exit `2` so the
orchestrator restarts the pod.

The local implementation models the reload decision in
`JitML.Service.HotReload` with `LiveConfigSnapshot` and `handleSighupReload`:
unchanged live config is ignored and changed live config increments the
generation.

## Health Endpoints and Logging

| Endpoint | Behaviour |
|----------|-----------|
| `/healthz` | Served by the in-binary HTTP runtime; live local-chart validation returns `200` with `ok` |
| `/readyz` | Served by the in-binary HTTP runtime; live local-chart validation returns `200` with `ready` after rollout |
| `/metrics` | Prometheus text served by the in-binary HTTP runtime, exposed in-cluster by the `jitml-service` local chart's ClusterIP Service on port `8080` |

Current logging support is pure JSON rendering. Target logging writes
structured JSON on stderr with fields `ts`, `level`, `msg`, `lifecyclePhase`,
`daemonId`, plus typed event payload. `LogLevel` is hot-reloadable.

## Recoverable vs Fatal Errors

| Class | Examples | Behaviour |
|-------|----------|-----------|
| Recoverable | `MinIOFailed (SEConflict)`, `MinIOFailed (SETimeout)`, `PulsarFailed (SETransient)`, `JitCacheMiss` | Retried via `RetryPolicy`; failure surfaces a structured warning |
| Fatal | `PrerequisiteUnmet`, `InvalidConfig`, `MinIOFailed (SEUnauthorized)`, `CheckpointFormatUnsupported` | Emit structured diagnostic; exit `2` |

## Capability Classes

| Class | Operations | Owning module |
|-------|-----------|---------------|
| `HasMinIO` | `minioPutIfAbsent`, `minioReadObject`, `minioReadBytes`, `putBlobIfAbsent`, `putBlobBytesIfAbsent`, `casPointer`, `listObjects`, `deleteObject` | `src/JitML/Service/Capabilities.hs`; local filesystem interpreter in `JitML.Service.FilesystemMinIO`; live HTTP S3 subprocess interpreter in `JitML.Service.MinIOSubprocess` |
| `HasPulsar` | `pulsarPublish`, `pulsarAcknowledge`, `pulsarSubscribe`, `pulsarConsume`, `pulsarSeek` | `src/JitML/Service/Capabilities.hs`; routed one-shot WebSocket subprocess interpreter and held-open worker surface in `JitML.Service.PulsarWebSocketSubprocess` |
| `HasHarbor` | `harborImageExists`, `harborPromoteImage`, `harborPushImage`, `harborPullImage`, `harborListImages` | `src/JitML/Service/Capabilities.hs`; explicit Docker/curl subprocess instance in `src/JitML/Service/HarborSubprocess.hs` |
| `HasKubectl` | `kubectlApply`, `kubectlStatus`, `kubectlGet`, `kubectlDelete` | `src/JitML/Service/Capabilities.hs` |

`JitML.Service.Clients` is the daemon acquisition settings layer. It derives a
`DaemonClientSettings` record from the loaded `BootConfig`, exposes the
`DaemonServiceClient` interpreter for all four capability classes, and
`DaemonRuntime` prints that record in the dry-run summary under
`client_acquisition`; the same summary prints the BootConfig-derived daemon
topic plan under
`pulsar_subscriptions` and per-topic startup acquisition state under
`pulsar_subscription_status`; the acquisition state comes from a one-shot
WebSocket consumer-open probe through the daemon's derived Pulsar settings with
`receiverQueueSize=0`, so acquisition does not prefetch pending work. The
summary also prints `client_probe_status` for the read-only MinIO list, Harbor
list, and kubectl get probes that run through the acquired non-Pulsar clients.
Cluster daemons target direct in-cluster endpoints: MinIO at
`http://minio.platform.svc.cluster.local:9000`, Pulsar WebSocket at
`ws://pulsar-broker.platform.svc.cluster.local:8080/ws`, Harbor API at
`http://harbor.platform.svc.cluster.local/api`, Harbor registry at
`harbor-registry.platform.svc.cluster.local:5000`, and kubectl through the
in-cluster service-account environment. The local chart creates
`ServiceAccount/jitml-service` plus namespace-scoped Role/RoleBinding so the
daemon can execute the current workload operations without mounting the host
kubeconfig into the pod. Apple host daemons derive the same settings from the
patched host Dhall: routed MinIO URLs are split into the root endpoint plus the
`/minio/s3` request-target prefix,
`pulsar://127.0.0.1:<edge>/pulsar` becomes
`ws://127.0.0.1:<edge>/pulsar/ws`, `127.0.0.1:<edge>/library` is split into
Docker registry root plus the routed `/harbor/api` base, and kubectl uses the
repo-local `./.build/jitml.kubeconfig`. The host-native Apple daemon
subscription path is live-validated on 2026-05-21 with
`jitml service --config ./.build/conf/host/apple-silicon.dhall --consume-once 0`
against the leased `127.0.0.1:9090` edge route; that run loads the patched Dhall,
passes MinIO / Harbor / kubectl probes, and acquires
`persistent://public/default/inference.command.apple-silicon` as `jitml-host`.

`HasPulsar`, `HasHarbor`, and `HasKubectl` operations route through the typed
`Subprocess` boundary where no native client is checked in. The current Pulsar
WebSocket interpreter targets `ws://127.0.0.1:<edge-port>/pulsar/ws`, which
Envoy rewrites to the broker-embedded `/ws` endpoint on `pulsar-broker:8080`.
It provides both one-shot validation surfaces and the normal daemon worker:
`pulsarSubscribe` opens the consumer endpoint with `receiverQueueSize=0` for
startup acquisition, `pulsarConsume` opens a consumer with a bounded receiver
queue, reads one message, stores the broker message id for the payload, and
closes; `pulsarAcknowledge` reopens the routed consumer endpoint and sends that
message id only after the Haskell dispatcher returns success.
`runPulsarConsumerWorker` starts a held-open consumer WebSocket for the normal
serve path, streams decoded deliveries to Haskell over stdout, and acks by
writing broker message ids back to the worker over stdin after dispatcher
success. Dispatch failures write a `negativeAcknowledge` command to the same
worker so Pulsar redelivers the broker message after the configured delay. The
Node scripts use `globalThis.WebSocket` when present and fall back to Node's
bundled `undici.WebSocket` for older runtimes. Current `jitml:local` carries
Node.js `22.16.0`. Live
validation on 2026-05-20 publishes and consumes on
`persistent://public/default/training.command.linux-cpu`, matching the current
daemon subscription topic family. 2026-05-21 live service-pod validation
publishes command messages on the daemon topics, runs
`jitml service --consume-once 1`, dispatches Training, Tune, RL, and Inference
before ack, applies the Training/Tune/RL Jobs, and separately dispatches
`WriteCheckpointBlob` workload-effect payloads into MinIO and
`PromoteWorkloadImage` payloads into Harbor same-repository tag promotion.
`jitml-integration`
validates that consume records broker message ids, that the explicit
acknowledge command sends the id after dispatch, and that the held-open worker
command streams payloads to Haskell, only acks after Haskell writes a broker
message id, and renders the negative-ack command used for dispatch failures.
Normal service startup now runs that dispatcher from held-open
workers with retained dedup state for the process lifetime, and 2026-05-21 live
Linux CPU validation proves that path for `RunInference` without
`--consume-once`; the same date validates duplicate-payload dedup and
dispatch-failure negative-ack redelivery against the running broker.
The daemon
now loads `BootConfig` from Dhall before starting the runtime and derives
concrete subprocess settings from those loaded coordinates. `jitml service`
crosses the derived Pulsar `pulsarSubscribe` acquisition boundary and the
read-only MinIO/Harbor/kubectl probe boundaries through `DaemonServiceClient`
before serving, and drops readiness when acquisition or probe fails. 2026-05-20
live validation of the Linux CPU chart confirms `/healthz`, `/readyz`,
`/metrics`, MinIO `jitml-checkpoints` listing, Harbor `library` listing, and
in-pod `kubectl get pods -n platform` through the `jitml-service` service
account. The same live path applies, reads, and deletes the current
Training/RL/Tune Job manifest shapes through that service account from inside
the running pod. `JitML.Service.Workload` is the current typed workload-effect runner
for mutating daemon effects: it maps checkpoint blob writes to
`HasMinIO.putBlobBytesIfAbsent`, checkpoint pointer updates to
`HasMinIO.casPointer`, image promotion to `HasHarbor.harborPromoteImage`, and
resource apply/status/delete to `HasKubectl`; `RunInference` loads the latest
checkpoint manifest through `HasMinIO` and publishes `InferenceResult` through
`HasPulsar`. It also renders/parses
byte-faithful `WorkloadEffect` payloads, and `daemonWorkloadDispatcher` routes
parsed payloads through those calls before ack. The same dispatcher maps parsed
Training/RL/Tune start/stop command envelopes into Kubernetes Job apply/delete
workload effects and maps `RunInference` request envelopes into the inference
effect before ack. The daemon lifecycle suite validates those calls
against the synthetic daemon client instance, and
`jitml service --consume-once <n>` is the bounded service-pod validation surface
for the same dispatcher; 2026-05-21 live Linux CPU validation exercises that
surface against the running service pod for the command-envelope path and for
`WriteCheckpointBlob`, `PromoteWorkloadImage`, and `RunInference` payloads.
Harbor
settings are passed as a value
(`HarborSettings`) containing registry/API coordinates, credentials, optional
Docker host socket, and the repo-local Docker config directory; the client does
not read process environment variables or write to the user's global Docker
config.

## RetryPolicy

`RetryPolicy` is a typed value with named strategies:

- `Once` — no retry.
- `LinearN k delayMs` — `k` retries with constant delay.
- `ExponentialN k baseMs cap` — `k` retries with capped exponential backoff.
- `RetryUntil deadline` — retry until the wall-clock deadline.

`retryServiceAction :: RetryPolicy -> (env -> IO a) -> env -> IO (Either
AppError a)` is the single retry harness.

Service-error kinds:

- `SEConflict` (retryable; from `If-Match`/`If-None-Match` `412`)
- `SEUnauthorized` (fatal)
- `SETimeout` (retryable per policy)
- `SETransient` (retryable per policy)

## TensorBoard Side Effects

The TensorBoard pod is stateless. A MinIO-client sidecar mirrors bucket
`jitml-tensorboard` into the pod's `/tensorboard/logs` `emptyDir`, and
TensorBoard serves that logdir behind `/tensorboard`. Live Linux CPU validation
on 2026-05-19 proves TFRecord shards written to MinIO appear in the scalars
API, including a Haskell-written shard sent through routed
`JitML.Service.MinIOSubprocess`. The daemon-side event writer owns the
long-lived shard buffer: `TensorBoardWriterState` tracks writer id, shard
sequence, file-version emission, buffered bytes, and start time;
`shouldRotateShard` decides when to flush; `encodeTfRecord` writes the TFRecord
frames; and `HasMinIO.putBlobBytesIfAbsent` performs write-once shard PUTs.

`JitML.Observability.TbSidecar.dispatchCheckpointDone` writes
`TbCheckpointMarker` CBOR sidecars through `HasMinIO`; filesystem-backed tests
and 2026-05-19 live routed MinIO validation cover the writer.
`dispatchCheckpointPayload` parses rendered `CheckpointDone` envelopes, and
`JitML.Service.Runtime.daemonTensorBoardDispatcher` invokes the sidecar write
from the daemon dispatcher contract before ack.

## At-Least-Once Pulsar Consumer

Per doctrine `At-Least-Once Event Processing`. Idempotency is the consumer's
responsibility; the typed `EventID` deduplication key is derived from the
protobuf message hash and is opaque to the broker.

- `EventID` is derived from the protobuf message hash. The daemon does not
  trust client-supplied IDs.
- `daemonSubscriptionsForBootConfig` derives the daemon subscription plan from
  loaded `BootConfig`: cluster-resident daemons subscribe to
  `training.command.<mode>`, `tune.command.<mode>`, `rl.command.<mode>`, and
  `inference.request.<mode>`; the Apple host daemon subscribes only to
  `inference.command.apple-silicon`.
- `JitML.Proto.Training.parseTrainingCommand`,
  `JitML.Proto.Rl.parseRlCommand`, and
  `JitML.Proto.Tune.parseTuneCommand` parse the deterministic local text
  command envelopes that the current renderers emit. Training, RL, and Tune
  command envelopes also have strict proto3-compatible byte codecs via
  `JitML.Proto.Wire`; Training, RL, and Tune event envelopes use the same
  local wire helper; `JitML.Proto.Inference` does the same for the
  `InferenceRequest` / `InferenceResult` topic envelopes declared in
  `proto/jitml/inference.proto`. Cross-language generated proto-lens bindings
  remain target work.
- Per-handler `dedupCache :: TVar (LRUSet EventID)` provides at-least-once
  → effectively-once for the duration the entry stays cached. Cache size
  and TTL are `LiveConfig` knobs; the current runtime uses both when
  constructing the per-domain handler router, and the local consumer expires
  dedup entries at the configured TTL boundary before deciding whether a
  redelivery is fresh.
- Acks are explicit; failure to ack within the `RetryPolicy` budget surfaces
  `AppError PulsarFailed`.
- A failed handler dispatch does not mark the event id as seen. The local
  consumer calls `HasPulsar.pulsarSeek` on that subscription cursor and keeps
  the dedup cache unchanged so broker redelivery can run the handler again.

The current consumer surface includes the payload-hash deduplication helper,
`JitML.Service.Consumer.{consumerStep,runConsumerLoop,ConsumerOutcome}`,
fully-qualified topic routing for live broker names under
`persistent://public/default/`, `daemonSubscriptionsForBootConfig`,
`subscribeDaemonTopics`, startup-summary rendering of those subscriptions,
per-topic acquisition status via
`JitML.Service.Runtime.acquireDaemonSubscriptions`, a routed WebSocket
subscribe probe in `JitML.Service.PulsarWebSocketSubprocess`, and per-domain
`HandlerRouter` dispatch coverage against a synthetic broker in
`jitml-daemon-lifecycle`. `JitML.Service.Runtime.daemonConsumerBatch` threads
acquired subscription statuses through the `LiveConfig`-sized router for a
bounded local batch, dispatching fresh events, deduplicating duplicate payload
hashes, skipping unroutable topics, and acking every delivery in the synthetic
broker test. The same lifecycle suite verifies a failed dispatch calls
`pulsarSeek`, does not poison the dedup cache, and allows the redelivery to
dispatch successfully. Pulsar bootstrap registers the matching
substrate-scoped 26-topic family before daemon
subscription, and 2026-05-20 live Linux CPU validation confirms all 26 current
topics exist in the broker. Live Pulsar publish/consume through the routed
broker WebSocket endpoint is validated by
`JitML.Service.PulsarWebSocketSubprocess`, and 2026-05-21 live service-pod
`--consume-once` validation covers bounded post-dispatch ack on the daemon
topics. Normal `jitml service` startup now creates per-acquired-subscription
held-open workers that share a process-lifetime `HandlerRouter`. 2026-05-21
live Linux CPU validation proves the held-open-worker path for a
`RunInference` request and reply without using `--consume-once`, then publishes
the same `RunInference` payload twice and observes exactly one matching
`InferenceResult`, and finally validates a missing-checkpoint dispatch failure
by observing zero results before seed and receiving the redelivered
`InferenceResult` after the checkpoint is seeded.

The current dispatcher has local command-handler coverage for the parsed text
envelopes that exist today: `StartTraining` / `StopTraining`,
`StartRLRun` / `StopRLRun`, and `StartSweep` / `StopSweep` map to
kubectl-backed Job apply/delete workload effects. Live service-pod validation
has proved those generated Job manifest shapes through the in-cluster service
account, and 2026-05-21 live `--consume-once` validation invokes the dispatcher
itself from the running service pod for those command envelopes and for MinIO
checkpoint writes plus Harbor same-repository image promotion. The same live
path seeds a latest checkpoint in MinIO, dispatches a bare-reply-topic
`RunInference` request, and consumes `InferenceResult` with output `1.01,2.01`
from `inference.result.linux-cpu`.

Checkpoint-backed inference uses the Phase 10 read path:
`JitML.Checkpoint.Store.loadInferenceCheckpointWith` loads the latest pointer
and manifest through `HasMinIO`, strips optimizer/RNG parts, and hands the
weight-only manifest to the active engine. The local Linux CPU validation path
uses `JitML.Engines.Local.runLinuxCpuCheckpointInference` to compile, load, and
execute a generated FFI kernel from that manifest. The daemon workload
dispatcher exposes the same hook through
`daemonWorkloadDispatcherWithInference`; `jitml service` selects the Linux CPU
generated-kernel runner for `linux-cpu` + `SelfInference` configs, so routed
`RunInference` messages invoke the FFI-backed checkpoint path before Pulsar
result publication. Production weight-blob loading into substrate-specific
engines remains Phase 10 / Phase 7 work.

## Apple Silicon Hybrid Pattern

Target Apple Silicon runtime: the clustered daemon (Dhall: `Cluster +
ForwardToHost`) runs the
`InferenceProxy`:

- On `inference.request.apple-silicon`, reads the model snapshot from MinIO,
  publishes an `inference.command.apple-silicon` envelope.
- Awaits the `inference.event.apple-silicon` ACK from the host daemon.
- Republishes on `inference.result.apple-silicon` to the demo frontend.

The host daemon (Dhall: `Host + SelfInference`) subscribes to
`inference.command.apple-silicon`, executes the kernel via Metal, writes
large outputs directly to MinIO, and ACKs on `inference.event.apple-silicon`
with the small envelope (call-id, kind tag, MinIO refs).
`JitML.Proto.Inference` owns the typed Apple-only command/event envelope
render/parse surface for those two topics. `JitML.Service.AppleInferenceRpc`
owns the local proxy plan: it converts a demo-facing `InferenceRequest` plus
starting snapshot into an Apple command envelope, publishes that command through
`HasPulsar`, records the client reply topic, and correlates completed/error
events by call id. The command envelope carries the call id,
training/inference kind, model id, starting snapshot, reply topic, and small
input descriptor; the event envelope carries completion/error kind, output
refs, and recoverable error fields.

`jitml bootstrap --apple-silicon` writes the cluster publication to
`./.build/runtime/cluster-publication.json` and the explicit live rollout patches
`./.build/conf/host/apple-silicon.dhall` with the routed Pulsar, MinIO, and
Harbor coordinates. The target live bootstrap then starts the host daemon from
that Dhall. Linux has no host-level Dhall; all JIT operations happen inside the
cluster daemon.

The current implementation renders the configs, topic names, lifecycle,
deployment surfaces, local HTTP endpoint server, BootConfig-derived client
settings, and BootConfig-derived daemon subscription plan; live host daemon
startup and service-loop Pulsar/MinIO flow remain target runtime validation.

The host daemon's startup path never touches tart. On a JIT cache miss the
daemon first validates or installs the `tart` Homebrew package through typed
lazy prerequisite remediation, then calls
`JitML.Tart.ensureVmUpLive jitml-build`, which is idempotent.
`JitML.Tart.Build` now renders the ordered cache-miss
plan that follows that handoff and the concrete executor behind it: inspect
`tart list --source local --format json`, start a stopped VM with
`tart run --no-graphics`, poll `tart exec <vm> true`, validate
`swift --version` in the VM, run `swift build` against the generated package,
publish `libJitMLMetal.dylib` into the content-addressed Apple cache, and
repoint the stable host FFI symlink. The same module exposes a typed executor
boundary whose unit tests validate ordered success and failure short-circuiting
with a synthetic executor. The user-facing `jitml internal vm
bootstrap|up|down|status` commands now dispatch to the same live Tart lifecycle
module for clone/status/start/stop operations. The live host daemon still needs
a provisioned or bootstrapped `jitml-build` VM and the Metal launch path.

Direct k8s API access from the host is hlint-forbidden.

## Generated Daemon Surface Table

<!-- jitml:daemon.surface:start -->
| Surface | Current owner | Current behavior |
|---------|---------------|------------------|
| `/healthz` | `JitML.Service.Runtime.daemonHttpRoutes` | Served by the in-binary HTTP runtime as a `200` response body |
| `/readyz` | `JitML.Service.Runtime.daemonHttpRoutes` | Served by the in-binary HTTP runtime with ready/not-ready status |
| `/metrics` | `JitML.Service.Runtime.daemonHttpRoutes` | Served by the in-binary HTTP runtime as Prometheus text |
| `BootConfig` | `JitML.Service.BootConfig` and `dhall/service/BootConfig.dhall` | Cluster/host residency, inference mode, Pulsar, MinIO, Harbor, HTTP listener fields |
| `LiveConfig` | `JitML.Service.LiveConfig` and `dhall/service/LiveConfig.dhall` | Log level, retry policy, tart idle timeout, inference batching/SLO, dedup cache size/TTL, drain deadline fields |
| SIGHUP reload decision | `JitML.Service.HotReload` | Pure reload/ignore/restart-required decision surface |
| POSIX signal wiring | `JitML.Service.Signal` and `JitML.Service.Runtime` | SIGHUP increments reload generation; SIGINT/SIGTERM begin graceful drain and drop readiness |
| Consumer idempotency | `JitML.Service.Consumer` | Pure payload-hash deduplication surface |
| HTTP listener | `JitML.Service.Http` | Low-level typed route server shared by `jitml service` and `jitml-demo` one-shot tests |
<!-- jitml:daemon.surface:end -->

## Cross-References

- [../../README.md → Apple Silicon hybrid pattern](../../README.md#apple-silicon-hybrid-pattern)
- [../../README.md → Pulsar as the control-plane ↔ data-plane bus](../../README.md#pulsar-as-the-control-plane--data-plane-bus)
- [haskell_code_guide.md](haskell_code_guide.md)
- [cluster_topology.md](cluster_topology.md)
- [../../DEVELOPMENT_PLAN/phase-5-jitml-service-daemon.md](../../DEVELOPMENT_PLAN/phase-5-jitml-service-daemon.md)

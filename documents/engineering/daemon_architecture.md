# Daemon Architecture

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-3-cluster-substrate-and-routing.md, ../../DEVELOPMENT_PLAN/phase-4-stateful-platform-services.md, ../../DEVELOPMENT_PLAN/phase-5-jitml-service-daemon.md, ../../DEVELOPMENT_PLAN/phase-7-jit-codegen-and-substrates.md, ../../DEVELOPMENT_PLAN/phase-8-supervised-and-rl-framework.md, ../../DEVELOPMENT_PLAN/phase-10-checkpointing-and-inference.md, ../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md, cluster_topology.md, haskell_code_guide.md, jit_codegen_architecture.md, purescript_frontend.md, training_workloads.md, durable_state_dsl.md, run_contract.md
**Generated sections**: daemon.surface

> **Purpose**: Project-specific `jitml service` daemon architecture — the
> service-not-host-service unification, BootConfig / LiveConfig, hot reload,
> health endpoints, structured logging, recoverable vs fatal errors,
> capability classes, retry policy, and at-least-once Pulsar consumer.

**Durable-state topic family (Sprint 5.15):** the logical Pulsar topic family is
declared by the durable-state registry and held consistent with the per-substrate
routing in `JitML.Coordinator.Topology` by a `jitml-unit` anti-drift test
(`topologyLogicalNames`). See [durable_state_dsl.md](durable_state_dsl.md).

Worker configuration follows the
[raw-to-validated run boundary](run_contract.md#raw-and-validated-boundaries): a
mounted versioned Dhall DTO is authoritative input. Supervised, Tune, and
AlphaZero transports carry only a canonical resolved plan, its content-derived
`PlanId`, and the operational Pulsar endpoint. Their loaders re-refine and
reject malformed, non-canonical, version-incompatible, or identity-mismatched
input before effects. Traditional RL retains a separately tracked primitive
adapter; the development plan owns that migration and validation status.

## Service Daemon Model

There is **one CLI verb for the daemon — `jitml service` — parameterised
entirely by its Dhall config**. No separate `host-service` verb. The Dhall
declares `substrate`, `residency`, `inferenceMode`, and host-side connection
info when `residency = Host`.

| Substrate | Daemon topology | Dhall configs |
|-----------|-----------------|----------------|
| `apple-silicon` | one clustered Coordinator plus one host Engine; clustered Engine replicas are zero | Coordinator ConfigMap from the materialized cluster config (`Cluster + ForwardToHost`) + host Engine file `./.build/conf/host/apple-silicon.dhall` (`Host + SelfInference`) |
| `linux-cpu` | three clustered Engine replicas plus one clustered Coordinator | Separate Engine and Coordinator ConfigMaps derived from `./.build/conf/cluster/linux-cpu.dhall` (`Cluster + SelfInference`) |
| `linux-cuda` | three clustered Engine replicas plus one clustered Coordinator | Separate Engine and Coordinator ConfigMaps derived from `./.build/conf/cluster/linux-cuda.dhall` (`Cluster + SelfInference`) |

The clustered Engine and Coordinator Deployments are **stateless** — durable
state lives in MinIO and Pulsar exclusively. Required Engine pod anti-affinity at
`topologyKey: kubernetes.io/hostname` enforces scoped numerical worker
cardinality. Linux substrates run three Engine replicas, one for each HA worker,
with `jitml.compute="true"` and `jitml.compute-scope="service"`. Daemon-spawned
Linux Training/RL/Tune Jobs carry `jitml.compute="true"` and
`jitml.compute-scope="workload"`. Service replicas and workload Jobs each match
their own scope in required hostname anti-affinity and hard topology spread, so
HA service residency and transient workload execution do not deadlock each
other. The single Coordinator is explicitly non-compute, uses its own
ServiceAccount, and owns namespace-scoped Job, per-run ConfigMap, and `pods/exec`
permissions; the Engine ServiceAccount has no workload-mutation Role. Apple Silicon's
Coordinator is the only clustered command daemon and host Metal work runs in
the host Engine. `maxSurge: 0` /
`maxUnavailable: 1` keeps rolling updates from temporarily exceeding compute
cardinality. 2026-05-23 live Linux CUDA validation historically proved the CUDA
RuntimeClass path against the compact topology; the current renderer preserves
that path on CUDA workers by rendering `runtimeClassName: nvidia`,
`NVIDIA_VISIBLE_DEVICES=all`, and
`NVIDIA_DRIVER_CAPABILITIES=compute,utility`. HA live revalidation is owned by
Phase `15` Sprint `15.22` and Phase `16` Sprint `16.14`.

Daemon diagnostics use the conjunctive selector
`app in (jitml-service,jitml-coordinator),jitml.role in (engine,coordinator)`.
The `app` clause restricts collection to the two daemon Deployments and the
`jitml.role` clause retains both command roles. Selecting only
`jitml.role=engine` is invalid because daemon-dispatched workload Jobs also
carry that execution-role label and may still be pending or
`ContainerCreating` when diagnostics are gathered.
Live Apple Silicon validation on 2026-05-23 historically completed
`./bootstrap/apple-silicon.sh up`, then ran the generated host Dhall through
`jitml service --consume-once 0` and acquired the
`inference.command.apple-silicon` subscription as `jitml-host`; the current host
plan also acquires the three workload host-command subscriptions and probes only
its Engine-owned MinIO capability.
Sprint `5.11` extends this two-daemon Apple topology from inference-only RPC to
Metal-backed Training/RL/Tune starts. The clustered Apple daemon remains the
orchestrator and owner of public substrate command topics; it does not render
Kubernetes Jobs for Apple work that needs `MlpDevice`/Metal execution, because
those Jobs run in Linux pods. Instead it plans such work as a host-resident
command carried by `training.host-command.apple-silicon`,
`tune.host-command.apple-silicon`, or `rl.host-command.apple-silicon`, with the
normal domain event topics used for completion.
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
| `acquire` | Acquire the role-specific capability profile and HTTP listener. Coordinator reconciles the exact topology-derived topic family through its retry policy before opening placement consumers; Engine opens only its compute consumers. On the Apple host, Engine first probes the host OS Metal runtime and fixed jitML Metal bridge, records `apple_metal_acquire`, and fails closed before subscribing if either is unavailable. It does not start Tart, run SwiftPM, unlock keychains, or depend on GUI-session state. |
| `ready` | `/readyz` flips to `200`. |
| `serve` | Process commands at-least-once until SIGTERM / SIGINT / SIGHUP-to-restart-required-field. |
| `drain` | Stop accepting new commands; finish in-flight; flush TensorBoard shards; final checkpoint flush. |
| `exit` | Release capabilities; close logger. |

This is the process lifecycle of the long-running daemon. Individual work
requests use the separate placement/evidence lifecycle in
[Typed Run Contract → Lifecycle State Machine](run_contract.md#lifecycle-state-machine);
daemon readiness does not constitute workload completion.

The implementation exposes these phases through a closed daemon state, renders
summaries, starts the in-binary HTTP listener, and derives readiness from the
evidence held by `Starting`, `Ready`, `Degraded`, and `Draining`. Coordinator
readiness additionally requires opaque exact-topic-family evidence before any
consumer connection or client probe can advance the state. POSIX drain keeps
the readiness endpoint available as `503` while in-flight consumer work settles,
then closes the listener and releases resources. Lifecycle and consumer
transitions emit filtered structured JSON on stderr.

Runtime hardening order is part of the daemon contract: POSIX signal handling,
readiness transitions, and graceful drain land before real Pulsar/MinIO/Harbor/
kubectl clients. The current local runner implements the signal/control surface
in `JitML.Service.Signal` and drops readiness when drain begins, so shutdown
semantics are deterministic before the daemon starts mutating external services.
The production `jitml` executable is linked with the threaded RTS; the
daemon-lifecycle stanza proves that capability against the actual built binary
with `+RTS -N1`. The shared HTTP listener masks the accepted-socket ownership
handoff into its connection thread. Server-push WebSocket routes race their
scoped handler against a read-side peer close/EOF watcher, so a quiet browser
disconnect cancels and joins the handler before the socket closes and cannot
retain its Pulsar subprocess, transcript files, or owned subscription.

## BootConfig and LiveConfig

`BootConfig` (start-time only; restart-required field changes force a full
restart):

| Field | Type | Purpose |
|-------|------|---------|
| `activeRole` | `Role` | `Engine \| Coordinator \| Webapp`; selects a disjoint subscription, probe, capability, and RBAC profile |
| `substrate` | `Substrate` | `apple-silicon \| linux-cpu \| linux-cuda` |
| `residency` | `Residency` | `Cluster \| Host` |
| `inferenceMode` | `InferenceMode` | `SelfInference \| ForwardToHost` |
| `pulsarServiceUrl` | `Text` | Pulsar broker URL |
| `pulsarAdminUrl` | `Text` | Pulsar admin URL |
| `minioEndpoint` | `Text` | MinIO S3 endpoint |
| `harborRegistry` | `Text` | Harbor registry/project image prefix, e.g. `harbor-registry.platform.svc.cluster.local:5000/library` in-cluster or `127.0.0.1:<edge-port>/library` from the host |
| `httpListener` | `Optional HttpListener` | None when `residency = Host` |
| `webappPulsarWsUrl` | `Optional Text` | Non-empty and present only for `activeRole = Webapp` |

`LiveConfig` (hot-reloadable on SIGHUP):

| Field | Type | Purpose |
|-------|------|---------|
| `logLevel` | `LogLevel` | Dynamic minimum level for the structured stderr sink |
| `retryPolicy` | `RetryPolicy` | Dynamic total-attempt/backoff or deadline policy for retryable daemon actions and Coordinator topic reconcile |
| `inferenceBatchSize` | positive `Natural` | Maximum compatible inference deliveries admitted to one batch |
| `inferenceMaxLatencyMillis` | positive `Natural` | Admission-to-handler/publication-entry monotonic latency budget for an inference batch |
| `dedupCacheSize` | `Natural` | Per-domain at-least-once dedup cache capacity |
| `dedupCacheTtlSeconds` | `Natural` | Target per-domain dedup entry lifetime |
| `drainDeadlineSeconds` | `Natural` | Graceful shutdown budget before forced exit |

Every accepted LiveConfig field has a live operational reader. Log emission
reads the atomic snapshot for every event; dispatch reads retry policy for every
command; the first delivery of each inference batch captures the current size
and latency policy; router reconfiguration reads dedup bounds; and shutdown plus
Apple-host registry drain read the current deadline. A reload affects subsequent
events, dispatches, batch admissions, and drain, but never mutates an already
admitted batch window.

The Dhall schemas at `dhall/service/{BootConfig,LiveConfig}.dhall` are present
for the current surface. `JitML.Service.BootConfig.loadBootConfig` uses
`Dhall.inputFile` for explicit `jitml service --config` files, then refines the
cross-field topology before a runtime can be built. Linux CPU/CUDA accept only
`Cluster + SelfInference`; Apple Silicon accepts `Cluster + ForwardToHost` or
the host Engine's `Host + SelfInference`. Host residency is Engine-only and has
no listener; cluster residency requires a non-empty listener with a port in
`1..65535`; the Webapp alone requires and owns `webappPulsarWsUrl`. Oversized
Dhall `Natural` ports are rejected before conversion to `Int`.

Role selection is exhaustive before runtime construction. Linux Engines consume
only `inference.request.<substrate>` as `jitml-engine`; Linux Coordinators
consume Training/Tune/RL placement commands as `jitml-coordinator`. The Apple
cluster Coordinator additionally consumes inference requests for host
forwarding, while the Apple host Engine consumes inference plus the three
host-command families as `jitml-host`. A cluster Apple Engine and every Webapp
have no compute-command plan. `service --consume-once` remains Engine-only, so
the diagnostic cannot make Coordinator or Webapp inherit Engine callbacks.

An explicit BootConfig loads the adjacent `LiveConfig.dhall` before service
startup; missing or malformed live configuration is an `InvalidConfig` failure
rather than a silent fallback to defaults.
`JitML.Service.Clients` turns those loaded endpoints into an opaque, closed
`DaemonRoleClientSettings` projection. Engine retains only
`EngineClientSettings` and runs through `EngineServiceClient`, whose only
instances are `HasMinIO` and `HasPulsar`; Coordinator alone retains the full
client settings and runs the Harbor/`kubectl` orchestration interpreter; Webapp
retains no daemon-client settings. Engine probes only MinIO. Coordinator first
reconciles the exact topic family and then probes MinIO, Harbor, and kubectl.
Service startup
opens one persistent typed Pulsar consumer per role-derived subscription;
connected workers form part of `Ready` evidence and connection loss degrades
readiness. Probe results are rendered under `client_probe_status` and any
required failure drops readiness. Live Linux CPU
validation on 2026-05-20 confirms those daemon-acquired read-only probes pass
from the running pod. `JitML.Service.Workload` provides the local mutating
workload-effect runner over the same capability classes for checkpoint blob
writes, checkpoint pointer CAS, Harbor image promotion, kubectl
apply/status/delete, and RunInference result publication.
`JitML.Service.Runtime.daemonWorkloadDispatcher`
parses rendered byte-faithful `WorkloadEffect` payloads and routes them
through that runner from the consumer dispatcher contract; it also maps parsed
Training/RL/Tune start/stop command envelopes into workload-placement decisions.
For Linux substrates, device-backed Training/RL/Tune commands may plan
Kubernetes Job apply/delete effects. For Apple Silicon, Metal-backed starts plan
a host-resident Pulsar command instead of an in-cluster Job; Linux pods cannot
load the host Metal bridge or execute macOS Metal runtime calls. Apple
Training/Tune/RL Stops are forwarded by the Coordinator to the same typed host
command topics as Starts. The host Engine refines `(workload family,
experiment hash)`, claims the matching registered `Async` handle exactly once,
cancels or naturally drains it according to the typed Stop mode, joins it, and
returns success only after observing the exact terminal outcome. A successful
join is retained against the semantic delivery `EventId`, so a required terminal
status-publication failure can Nack and redeliver the same Stop without losing
the receipt; a distinct Stop still observes the terminal tombstone and fails
closed. Unknown, already-stopping, already-terminal, duplicate-Start, and
completion-race cases fail closed.
`jitml
service --consume-once <n>` runs bounded persistent consumption through the
Engine's BootConfig-derived minimal client and renders dispatch / dedup /
disposition outcomes before exiting. It joins every Apple host workload handle
registered by the bounded pull and surfaces retained worker failures before
reporting success; an explicit `--consume-once 0` performs probes and exits
without pulling broker messages.
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
Pulsar. The normal `jitml service` serve path starts a persistent WebSocket
interpreter for each opaque subscription and keeps one handler router per
worker. Non-inference deliveries produce one disposition. Inference workers use
the multi-receipt batching interpreter: each compatible batch captures the
current size/latency policy. Sparse collection closes at the smaller of one
millisecond and one tenth of the captured latency budget. The deployed default
budget is five seconds, yielding a captured handler/publication-entry deadline.
The transport timeout cancels a handler that has not returned and Nacks the
admitted receipt set with `RetryRequested`. Dispatch commits semantic dedup
state one command at a time, so successful prefix commands remain committed if
a later command is cancelled and the broker redelivers the Nacked batch. Engine
samples the same deadline immediately before each Pulsar publication and refuses
to enter that side effect after expiry.

A handler decision that does return is not retroactively converted to a Nack by
a later clock sample: publication may already be externally visible, and broker
acknowledgement or publication completion may occur after the deadline. Pulsar
therefore remains at-least-once rather than providing an atomic batch or
globally exactly-once guarantee. The bridge confirms every commanded or
drain-race settlement after its socket write flushes before reporting `Drained`;
settlement, drain/protocol, bridge-process, and cleanup failures remain typed.
The daemon keeps the HTTP listener active while workers drain messages.
2026-05-21 live Linux CPU
validation proves the historical held-open path handles
`RunInference` and publishes the expected `InferenceResult` without
`--consume-once`, proves duplicate payloads produce exactly one matching
`InferenceResult`, and proves a missing-checkpoint dispatch failure is
negative-acked until broker redelivery publishes the result after the checkpoint
is seeded.

Worker Jobs read their versioned transport mounted at `/etc/jitml/run/` before
consulting any explicitly developer-only fallback. Supervised, Tune, and
AlphaZero mounts contain the canonical resolved plan and `PlanId`; they do not
repeat primitive budgets or selector axes, and a corrupt or mismatched transport
fails before workload effects. The surviving traditional-RL primitive adapter
is tracked separately in the development plan. See [Typed Plans and
Dimensional Budgets](run_contract.md#typed-plans-and-dimensional-budgets).

The live `chart/local/jitml-service` ConfigMap carries the same current Dhall
surface: residency and inference mode use typed union constructors, and
`LiveConfig` uses `logLevel`, `retryPolicy`, `inferenceBatchSize`,
`inferenceMaxLatencyMillis`, `dedupCacheSize`, `dedupCacheTtlSeconds`, and
`drainDeadlineSeconds`. The chart renders separate Engine and Coordinator
ConfigMaps, Deployments, ServiceAccounts, probes, selectors, and scoped RBAC;
unsupported no-op fields and the former Tart idle/build-VM fields are absent.
The Engine Deployment preserves its existing immutable app-only selector while
the pod template retains `jitml.role: engine` for role-indexed operation.
Both command-role Deployments use a bounded five-minute `/healthz` startup probe
before liveness begins, covering topic reconciliation, persistent consumer
connection, and client probes without allowing an unbounded startup.

## Hot Reload

SIGHUP handling is wired through `JitML.Service.Signal` and the actual service
loop. A signal is only a reload request; it does not increment generation by
itself. The daemon rereads the original BootConfig and its adjacent
`LiveConfig.dhall`, retains the last-good live snapshot on malformed input, and
ignores an unchanged snapshot without incrementing. A valid changed LiveConfig
is applied atomically through `JitML.Service.HotReload`, after which generation
increments exactly once. Any BootConfig change or malformed replacement is
restart-required: readiness drops, in-flight work drains using the latest valid
deadline, and the process exits with `AppError InvalidConfig` so the
orchestrator restarts it.

The active snapshot is shared with consumer workers. Reloaded dedup capacity
and TTL resize/prune each handler router while retaining the newest entries that
remain valid; shutdown reads the current snapshot's drain deadline rather than
a startup copy. The structured logger reads the next level threshold, dispatch
reads the next retry policy, and a newly admitted inference batch reads the next
size/latency pair. Existing batch windows retain their admission-time snapshot.
Oversized or non-positive Dhall Naturals are rejected before `Int` conversion
where the corresponding operational boundary requires a positive value.

## Health Endpoints and Logging

| Endpoint | Behaviour |
|----------|-----------|
| `/healthz` | Served by the in-binary HTTP runtime; live local-chart validation returns `200` with `ok` |
| `/readyz` | Served by the in-binary HTTP runtime; live local-chart validation returns `200` with `ready` after rollout |
| `/metrics` | Prometheus text served by the in-binary HTTP runtime, exposed in-cluster by the `jitml-service` local chart's ClusterIP Service on port `8080` |

The `jitml-service` ClusterIP selects only the Coordinator. After applying the
Gateway and HTTPRoutes, live bootstrap performs a bounded retrying public
`/readyz` request. Linux then re-measures the Engine and Coordinator Deployments;
Apple re-measures only the clustered Coordinator and public edge. Apple records
no Engine component: the clustered Engine has zero replicas and the separately
launched host daemon is not part of cluster-bootstrap readiness.
`cluster-publication.json` is written only when every substrate-required
component has exactly one `ready` row; missing, duplicate, unexpected, or
not-ready role/edge evidence fails bootstrap without minting a live marker.

The daemon creates one process identity from its PID plus monotonic start time,
then writes structured JSON on stderr with fields `ts`, `level`, `msg`,
`lifecyclePhase`, and `daemonId`. Every emission reads the atomic LiveConfig
snapshot before applying the ordered `Debug < Info < Warn < Error` threshold,
so a valid SIGHUP level change governs the next event without rebuilding the
logger. Consumer-ready, outcome, and error paths use this operational sink.

## Recoverable vs Fatal Errors

| Class | Examples | Behaviour |
|-------|----------|-----------|
| Recoverable | `SEConflict`, `SETimeout`, `SETransient` | The command dispatcher reads the active `RetryPolicy`, performs real monotonic sleeps/backoff, and retains the final typed service error for settlement/logging |
| Fatal | `SEUnauthorized`, `PrerequisiteUnmet`, `InvalidConfig`, `CheckpointFormatUnsupported` | Stops retry immediately and maps to the typed `AppError`/structured diagnostic boundary |

## Capability Classes

| Class | Operations | Owning module |
|-------|-----------|---------------|
| `HasMinIO` | `minioPutIfAbsent`, `minioReadObject`, `minioReadBytes`, `putBlobIfAbsent`, `putBlobBytesIfAbsent`, `casPointer`, `listObjects`, `deleteObject` | `src/JitML/Service/Capabilities.hs`; local filesystem interpreter in `JitML.Service.FilesystemMinIO`; live HTTP S3 subprocess interpreter in `JitML.Service.MinIOSubprocess` |
| `HasPulsar` | Typed publication and scoped typed subscriptions; single and batched subscriptions yield receipt-hidden decoded deliveries and the interpreter settles each handler disposition | `src/JitML/Service/Capabilities.hs`; persistent single-/multi-receipt WebSocket interpreters in `JitML.Service.PulsarWebSocketSubprocess` |
| `HasHarbor` | `harborImageExists`, `harborPromoteImage`, `harborPushImage`, `harborPullImage`, `harborListImages` | `src/JitML/Service/Capabilities.hs`; explicit Docker/curl subprocess instance in `src/JitML/Service/HarborSubprocess.hs` |
| `HasKubectl` | `kubectlApply`, `kubectlStatus`, `kubectlGet`, `kubectlDelete` | `src/JitML/Service/Capabilities.hs` |

`JitML.Service.Clients` is the daemon acquisition settings layer. It derives a
closed role projection from the loaded `BootConfig`: opaque Engine settings and
an `EngineServiceClient` with only MinIO/Pulsar instances, full Coordinator
settings with the Harbor/kubectl interpreter, or no daemon clients for Webapp.
`DaemonRuntime` retains and prints only that projection under
`client_acquisition`; the same summary prints the BootConfig-derived opaque
daemon subscription plan under `pulsar_subscriptions`. Live consumer connection
state is runtime readiness evidence rather than an independently rendered
acquisition Boolean. The summary also prints role-specific
`client_probe_status`: MinIO for Engine; MinIO, Harbor, and kubectl for
Coordinator.
Cluster daemons target direct in-cluster endpoints: MinIO at
`http://minio.platform.svc.cluster.local:9000`, Pulsar WebSocket at
`ws://pulsar-broker.platform.svc.cluster.local:8080/ws`, Harbor API at
`http://harbor.platform.svc.cluster.local/api`, Harbor registry at
`harbor-registry.platform.svc.cluster.local:5000`, and kubectl through the
in-cluster service-account environment. The local chart creates
`ServiceAccount/jitml-engine` with no workload-mutation Role and disables
service-account-token automounting in Engine pods. It creates
`ServiceAccount/jitml-coordinator` with namespace-scoped Job, pod-read, and
`pods/exec` permissions, so cluster orchestration does not require the host
kubeconfig in a pod. Webapp likewise disables service-account-token automounting
and never requests the NVIDIA RuntimeClass or device environment. Apple host
daemons derive only Engine settings from the patched host Dhall: routed MinIO
URLs are split into the root endpoint plus the `/minio/s3` request-target prefix,
`pulsar://127.0.0.1:<edge>/pulsar` becomes
`ws://127.0.0.1:<edge>/pulsar/ws`; no Harbor credentials or kubectl configuration
are constructed or retained. The host-native Apple daemon
subscription path is live-validated on 2026-05-21 with
`jitml service --config ./.build/conf/host/apple-silicon.dhall --consume-once 0`
against the leased `127.0.0.1:9090` edge route; that historical run loads the patched Dhall,
passes the then-shared probes, and acquires
`persistent://public/default/inference.command.apple-silicon` as `jitml-host`.
The host workload subscriptions are derived from the same
`BootConfig { substrate = apple-silicon, residency = Host }` boundary rather than
from Kubernetes discovery; the host subscribes as `jitml-host` to
`training.host-command.apple-silicon`, `tune.host-command.apple-silicon`, and
`rl.host-command.apple-silicon`. The cluster reaches the host only through Pulsar
envelopes and MinIO object refs.

`HasPulsar`, `HasHarbor`, and `HasKubectl` operations route through the typed
`Subprocess` boundary where no native client is checked in. The Pulsar
WebSocket interpreter targets `ws://127.0.0.1:<edge-port>/pulsar/ws`, which
Envoy rewrites to the broker-embedded `/ws` endpoint on
`pulsar-broker:8080`. Its binding target is one persistent, scoped consumer
session: decoded deliveries retain their broker receipt, the Haskell handler
returns one disposition, and the interpreter settles that receipt on the same
session. Broker delivery identity is therefore no longer payload-derived. After
strict typed decode, `JitML.Service.Consumer` derives an opaque semantic
`PlanId` and then an `EventId` from that plan, the decoded command kind, and its
logical key. Alternate text/protobuf encodings of the same typed command agree,
while broker receipts remain a separate settlement identity. See
[Delivery and Settlement](run_contract.md#delivery-and-settlement). The daemon
now loads `BootConfig` from Dhall before starting the runtime and derives
concrete subprocess settings from those loaded coordinates. `jitml service`
opens the derived scoped Pulsar consumers and crosses its role-specific probe
boundaries through `EngineServiceClient` or the Coordinator interpreter before
serving, and drops readiness
when a required topic reconciliation, consumer, or probe fails. 2026-05-20
live validation of the Linux CPU chart confirms `/healthz`, `/readyz`,
`/metrics`, MinIO `jitml-checkpoints` listing, Harbor `library` listing, and
in-pod `kubectl get pods -n platform` through the historical shared service
account. The current Coordinator-only profile owns those Harbor/kubectl probes
and mutations. `JitML.Service.Workload` is the current typed workload-effect runner
for mutating daemon effects: it maps checkpoint blob writes to
`HasMinIO.putBlobBytesIfAbsent`, checkpoint pointer updates to
`HasMinIO.casPointer`, image promotion to `HasHarbor.harborPromoteImage`, and
resource apply/status/delete to `HasKubectl`; `RunInference` loads the latest
checkpoint manifest through `HasMinIO` and publishes `InferenceResult` through
`HasPulsar`. It also renders/parses
byte-faithful `WorkloadEffect` payloads, and `daemonWorkloadDispatcher` routes
parsed payloads through those calls before ack. On Linux lanes, the same
dispatcher maps parsed Training/RL/Tune start/stop command envelopes into Kubernetes Job apply/delete
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

The daemon writes the worker's canonical resolved supervised, Tune, or
AlphaZero plan by experiment hash; the worker also mounts `BootConfig.dhall` for
substrate and Pulsar wiring. The plan compiler, not the daemon renderer or
worker entry point, is the only place that interprets those training,
evaluation, sampler, scheduler, pruner, trial, or self-play budgets. Traditional
RL remains the explicitly tracked primitive exception. See [Typed Plans and
Dimensional Budgets](run_contract.md#typed-plans-and-dimensional-budgets).

## RetryPolicy

`RetryPolicy` is a typed value with named strategies:

- `Once` — no retry.
- `LinearN k delayMs` — `k` total attempts with constant delay between them.
- `ExponentialN k baseMs cap` — `k` total attempts with capped exponential
  delay between them.
- `RetryUntil deadlineMs` — retry until the elapsed monotonic deadline.

`retryServiceActionEither :: RetryPolicy -> (env -> IO (Either ServiceError a))
-> env -> IO (Either ServiceError a)` is the production scheduler;
`retryServiceActionWith` injects its monotonic clock and sleeper for deterministic
tests. Non-retryable errors stop immediately. The daemon captures the active
policy for each command, while Coordinator acquisition uses the startup
snapshot for exact topic-family reconcile. Cluster-bootstrap compatibility uses
its own bounded typed-Haskell loop over exact subprocess outcomes.

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
`checkpointDoneToMarker` converts an already-decoded typed `CheckpointDone`
event, and `dispatchCheckpointDone` writes its marker. The removed raw payload
parser and raw runtime dispatcher are not parallel protocol boundaries.

## At-Least-Once Pulsar Consumer

The daemon implements the shared receipt-bound rules in
[Typed Run Contract → Delivery and Settlement](run_contract.md#delivery-and-settlement).
In particular:

- semantic `EventId` values provide idempotency, while opaque broker receipts
  identify deliveries; neither substitutes for the other;
- `daemonSubscriptionsForBootConfig` derives Linux Engine inference, Linux
  Coordinator placement, Apple Coordinator placement/forwarding, and Apple host
  Engine command subscriptions from loaded `BootConfig` and the canonical
  topology;
- command and event bytes decode strictly into workload-specific typed values
  before dispatch; semantic identity is plan-, kind-, and logical-key-bound;
- a persistent consumer session yields a receipt-bearing delivery, the handler
  returns `Continue` or `Done` carrying one `Ack` or `Nack`, and the interpreter
  performs settlement only after the handler decision;
- inference dispatch commits semantic dedup transitions per command, preserving
  successful prefix commits if a later command is cancelled;
- failed decode, dispatch, settlement, drain/protocol, bridge-process, or cleanup
  remains a typed failure and cannot poison the semantic dedup cache; and
- subscriptions are scoped resources: `Owned` ephemeral subscriptions are
  deleted idempotently during cleanup, while `Borrowed` daemon subscriptions
  survive process shutdown.

The `jitml inference run` request/reply client opens its correlated reply
subscription `FromLatest` with `Owned` scope before publishing. Its reply
consumer accepts a result only when both `callId` and experiment hash match the
request; a same-call result for another experiment is unrelated. Every success,
timeout, publish failure, or exceptional exit cancels and joins that supervised
`Async` before the CLI returns. Joining keeps the transport's drain and
idempotent admin `DELETE` inside the owner scope. The DELETE is
cancellation-safe and bounded by explicit curl connection and total-time
limits. Settlement, drain/protocol, bridge-process, and cleanup failures
observed during cancellation remain typed; only a completely successful drain
and cleanup rethrows the original asynchronous exception. A live
request/reply-path failure maps to `PulsarFailed`, not checkpoint absence.
The lifecycle algebra and release classification live in
`JitML.Service.InferenceReplyScope`; its two public supervisors are non-inlining
boundaries so the library's exposed unfoldings do not reintroduce their
higher-order cleanup Core into the CLI composition module.

Inference uses `pulsarConsumeBatchesUntil`, the multi-receipt form of the same
capability. The transport permits one broker delivery at a time while admitting
a compatible batch, retains every receipt privately, and stops sparse
collection at the earlier collection cutoff. The timeout owns the handler
deadline, while Engine independently refuses to enter publication after the
same captured deadline. If no handler decision returns, the transport cancels
the handler and Nacks the admitted set; if a decision returns, the transport
settles it without a retroactive clock-based Nack because publication may
already be visible. Every hidden receipt, including a delivery racing drain,
must flush and settle before `Drained`. Decode failure Nacks the admitted set and
fails the session; SLO expiry Nacks the set with `RetryRequested` and continues.
A policy reload applies only when the next batch admits its first delivery.

Linux CPU/CUDA typed start commands select cluster-Job placement; Apple
Metal-backed starts select host-run placement and cannot produce a Linux
workload Job. Live integration scenarios use the shared live-workflow
interpreter, terminal/evidence join, structured observation states, exact
evidence reducers, and diagnostics-before-cleanup boundary described by
[Functional Core, Imperative Shell](run_contract.md#functional-core-imperative-shell).

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

The Apple Silicon Coordinator (Dhall: `Cluster + ForwardToHost`) forwards
inference rather than computing it (Metal cannot run in-pod):

- On `inference.request.apple-silicon`, it decodes every inference-domain
  command — `RunInference`, `CheckpointCompareCommand`, and
  `AdversarialMoveCommand` — and publishes it through the canonical typed
  encoder for `inference.command.apple-silicon`.
- It does not await or republish a reply: the host Engine publishes the result
  to the request's reply-topic (`inference.result.apple-silicon`) directly.

The host daemon (Dhall: `Host + SelfInference`) is the Engine for
`apple-silicon`: it subscribes to `inference.command.apple-silicon`, runs the
Metal weighted kernel, and publishes the matching `InferenceResult` /
`CheckpointCompareResult` / `AdversarialMoveResult` (inline output values, the
converged values model) to the request's reply-topic, where the `jitml
inference run` CLI and the Webapp panels read it. `JitML.Proto.Inference` owns
the typed command/result render/parse surface; canonical re-encoding preserves
the values-model command family rather than converting it into a separate
refs-carrying envelope, so the host reply remains the `InferenceResult` the
client expects.

The same Coordinator forwards Training, Tune, RL, and AlphaZero Starts and
Stops to their typed host-command topics. The host Engine registers long-running
Starts under a refined family/hash key before releasing the worker action.
Natural completion and failure become retained terminal tombstones. Stop can
claim a running handle once, then returns success only after cancellation and
join; it never deletes a nonexistent Kubernetes Job or publishes an early false
terminal status. SIGTERM closes registry admission and joins all active host
actions under the current LiveConfig drain deadline.

`jitml bootstrap --apple-silicon` writes the cluster publication to
`./.build/runtime/cluster-publication.json` and the explicit live rollout patches
`./.build/conf/host/apple-silicon.dhall` with the routed Pulsar, MinIO, and
Harbor coordinates. The live bootstrap then starts the host daemon from that
Dhall. Linux has no host-level Dhall; numerical Jobs and clustered Engines
perform its JIT work.

The implementation renders separate role configs, topic names, lifecycle,
deployment/RBAC surfaces, BootConfig-derived client settings, and
BootConfig-derived daemon subscription plans. Cluster daemons expose the configured HTTP endpoint;
host daemons preserve `httpListener = None` and run without an operator listener
while their Pulsar workers consume host-resident work. Live Apple bootstrap,
host daemon startup, fixed-bridge execution, and the service-loop Pulsar/MinIO
flow are validated by the 2026-06-12 Apple `WorkflowMatrix` run and the
2026-06-13 full `bootstrap/apple-silicon.sh test` lane, which passed with no
Apple Metal-backed workload Jobs.

The Apple Silicon daemon owns no build VM. On `AppleSilicon + SelfInference`,
startup probes `apple.metal-runtime` and `apple.metal-bridge`, surfaces that
state in the daemon summary, and exits with a prerequisite error before Pulsar
subscription if the fixed bridge cannot be loaded/probed. The cache-miss
path writes `<hash>.metal.json` MSL source metadata and asks the fixed bridge to
compile with `MTLDevice.makeLibrary(source:options:)` in-process on the host GPU
with fast math disabled. There is no daemon-owned Tart lifecycle, SwiftPM build,
offline `metal` compiler invocation, or keychain-dependent step in this path.

Direct k8s API access from the host is hlint-forbidden.

## Generated Daemon Surface Table

<!-- jitml:daemon.surface:start -->
| Surface | Current owner | Current behavior |
|---------|---------------|------------------|
| `/healthz` | `JitML.Service.Runtime.daemonHttpRoutes` | Served by the in-binary HTTP runtime as a `200` response body |
| `/readyz` | `JitML.Service.Runtime.daemonHttpRoutes` | Derived from closed daemon-state evidence; remains observable as `503` throughout graceful drain |
| `/metrics` | `JitML.Service.Runtime.daemonHttpRoutes` | Served by the in-binary HTTP runtime as Prometheus text |
| `BootConfig` | `JitML.Service.BootConfig` and `dhall/service/BootConfig.dhall` | Engine/Coordinator/Webapp role selects disjoint subscriptions, probes, capabilities, residency, inference mode, and listener ownership |
| `LiveConfig` | `JitML.Service.LiveConfig` and `dhall/service/LiveConfig.dhall` | Operational hot fields: log threshold, retry policy, inference batch size/latency, dedup cache size/TTL, and drain deadline |
| SIGHUP reload decision | `JitML.Service.HotReload` | Pure reload/ignore/restart-required decision surface |
| POSIX signal wiring | `JitML.Service.Signal` and `JitML.Service.Runtime` | SIGHUP requests a reread; only a valid changed LiveConfig increments generation. SIGINT/SIGTERM enter `Draining`, settle in-flight work within the active deadline, then close the listener |
| Structured daemon logger | `JitML.Service.Logger` | One process identity; every JSON stderr emission reads the active LiveConfig threshold |
| Service retry scheduler | `JitML.Service.Retry` | Retryable typed service errors use real monotonic delay/backoff; each dispatch reads the active policy |
| Typed Pulsar topology | `JitML.Coordinator.Topology` | Hidden-constructor protocol topics and opaque borrowed/owned subscriptions derived from the validated 34-route topology |
| Coordinator topic acquire | `JitML.Cluster.PulsarBootstrap` and `JitML.Service.RuntimeState` | Create/already-exists observations refine to exact-family evidence; readiness rejects duplicate, missing, unexpected, or unreconciled topics |
| Persistent delivery settlement | `JitML.Service.Capabilities` and `JitML.Service.PulsarWebSocketSubprocess` | Single- and multi-receipt consumers hide receipts; every commanded or drain-race settlement is socket-flush-confirmed before continuation or `Drained`, and settlement/drain/process/cleanup failures remain typed |
| Inference batching/SLO | `JitML.Service.InferenceBatch` and `JitML.Service.PulsarWebSocketSubprocess` | Admission snapshots positive size/latency and a handler/publication-entry deadline; timeout cancels and Nacks when no decision returns, Engine refuses publication entry after expiry, returned decisions are not retroactively Nacked, and broker delivery remains at-least-once |
| Apple host workload registry | `JitML.Service.HostWorkloadRegistry` | Refined family/hash keys supervise registered `Async` handles; Stop and bounded drain succeed only after exact cancellation/join |
| Daemon runtime state | `JitML.Service.RuntimeState` | `Starting`, `Ready`, `Degraded`, and `Draining` carry topic-family, connection, probe, and failure evidence without an independent readiness Boolean |
| Indexed workload effects | `JitML.Service.Workload` | Non-empty effect programs pair each effect kind with only its legal result and placement |
| Consumer idempotency | `JitML.Service.Consumer` | Strictly decoded commands derive opaque semantic `EventId` values from `PlanId`, command kind, and logical key; per-command commits survive later batch cancellation, while broker receipts remain separate at-least-once settlement identities |
| HTTP listener | `JitML.Service.Http` | Low-level typed route server shared by `jitml service` and Webapp route tests |
<!-- jitml:daemon.surface:end -->

## Cross-References

- [../../README.md → Apple Silicon hybrid pattern](../../README.md#apple-silicon-hybrid-pattern)
- [../../README.md → Pulsar as the control-plane ↔ data-plane bus](../../README.md#pulsar-as-the-control-plane--data-plane-bus)
- [haskell_code_guide.md](haskell_code_guide.md)
- [run_contract.md](run_contract.md)
- [cluster_topology.md](cluster_topology.md)
- [../../DEVELOPMENT_PLAN/phase-5-jitml-service-daemon.md](../../DEVELOPMENT_PLAN/phase-5-jitml-service-daemon.md)

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
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Stand up the current `jitml service` daemon surface — the
> registered CLI entrypoint, Dhall `BootConfig` / `LiveConfig` renderers,
> lifecycle, endpoint, logging, retry, payload-hash deduplication, SIGHUP
> reload decisions, capability-class boundaries, and stateless `Deployment`
> rendering — while keeping live Pulsar/Harbor clients and daemon-acquired
> MinIO wiring explicit as target runtime validation.

## Phase Status

🔄 **Active**. The phase owns
[Exit Definition](README.md#exit-definition) item 2 (`jitml service` is
the canonical long-running daemon, parameterised by Dhall `BootConfig` /
`LiveConfig`, hot-reloadable via SIGHUP, exposing `/healthz` / `/readyz` /
`/metrics`, emitting structured JSON logs on stderr, processing Pulsar
events at-least-once with the typed retry policy). **Met today**:
Sprints `5.1`, `5.2`, `5.3` close the daemon entry point, the BootConfig
/ LiveConfig ADTs and Dhall renderers, the in-binary HTTP listener
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
LRU `DedupCache` are checked in. **Unmet today**: Sprint `5.4` owes
daemon acquisition for the live Pulsar, Harbor, MinIO, and kubectl clients
against the running cluster; the standalone live MinIO capability path is
validated through `JitML.Service.MinIOSubprocess`, and the standalone routed
Pulsar publish/consume path is validated through
`JitML.Service.PulsarWebSocketSubprocess`. Sprint `5.5`
owes the daemon's long-lived Pulsar redelivery/ack/seek path using the typed
router; Sprint `5.6`
owes validated pod anti-affinity across multiple replicas plus Apple host
Dhall connectivity; single-replica deployment readiness is already covered
by the live bootstrap validation. Detailed remaining work lives in those sprints'
`### Remaining Work` blocks below.

### Current Implementation Scope

The worktree implements `BootConfig` / `LiveConfig` ADTs and Dhall
renderers, lifecycle phase data, hot-reload decision data, pure
endpoint-response rendering, pure JSON log rendering, service
error/retry helpers, payload-hash deduplication, capability-class
definitions, and chart ConfigMap/Deployment rendering, the POSIX
signal/control surface in `src/JitML/Service/Signal.hs`, and the
low-level in-binary HTTP runtime in
`src/JitML/Service/{Http,Runtime}.hs` serving `/healthz`, `/readyz`, and
`/metrics`. `SIGHUP` increments the reload generation; `SIGINT` and
`SIGTERM` begin graceful drain and drop readiness. The filesystem-backed
`HasMinIO` instance, live HTTP-backed `JitML.Service.MinIOSubprocess`
instance, one-shot routed `JitML.Service.PulsarWebSocketSubprocess` instance,
and subprocess-backed `HasKubectl` instance are checked in and covered locally /
behind the live path; daemon-acquired Pulsar/Harbor/MinIO/kubectl clients are
owned by Sprints `5.4`–`5.6`.

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
- `src/JitML/App.hs` renders the lifecycle, BootConfig/LiveConfig, endpoint,
  and metrics summaries, then starts `ServiceRuntime.serveDaemon` for the
  command.
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
  - `drainDeadlineSeconds`
- `JitML.Service.HotReload` models the local reload snapshot and SIGHUP reload
  decision: unchanged `LiveConfig` is ignored, changed `LiveConfig` increments
  the generation.
- `JitML.Service.Signal` wires POSIX `SIGHUP`, `SIGINT`, and `SIGTERM` into the
  daemon control surface: `SIGHUP` increments the reload generation, while
  `SIGINT` / `SIGTERM` begin graceful drain and make `/readyz` report not ready.
  Restart-required field changes (i.e., any `BootConfig` field) remain modelled
  as `AppError InvalidConfig` so the orchestrator restarts the pod.
- The Dhall schemas at `dhall/service/{BootConfig,LiveConfig}.dhall` are present
  and match the renderers; target Haskell decoders use `Dhall.input`.

### Validation

1. `jitml service` renders the current BootConfig and LiveConfig summaries.
2. `dhall/service/BootConfig.dhall` and `dhall/service/LiveConfig.dhall`
   exist and match the current renderer vocabulary.
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

## Sprint 5.4: `RetryPolicy` and Service Error Surface 🔄

**Status**: Active
**Implementation**: `src/JitML/Service/Retry.hs`,
`src/JitML/Service/Capabilities.hs`
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
   `JitML.Service.PulsarWebSocketSubprocess`. Remaining live targets:
   daemon-acquired `HasPulsar` uses a long-lived subscription with post-dispatch
   ack/redelivery and seek semantics; daemon-acquired `HasHarbor` pushes/pulls
   an image against real Harbor; `HasKubectl` invokes `kubectl get pods`
   against the cluster's kubeconfig.

### Remaining Work

- The four typed capability classes now expose the full current method
  set: `HasMinIO` includes text and byte read/write helpers plus
  conditional write/CAS/list/delete; `HasPulsar` includes publish,
  acknowledge, subscribe, consume, and seek; `HasHarbor` includes
  exists/promote/push/pull/list; `HasKubectl` includes apply, status,
  get, and delete. The typed `ETag` and `SubscriptionId` newtypes carry
  the broker / store cursor identities through the capability boundary.
- The filesystem-backed instance `JitML.Service.FilesystemMinIO`
  honours `putBlobIfAbsent` (412 → `SEConflict`) and `casPointer`
  (`If-Match: <etag>` → `SEConflict`); validated by `jitml-integration`.
  `JitML.Service.MinIOSubprocess` is the live HTTP-backed `HasMinIO`
  instance against the running MinIO service; 2026-05-19 live validation
  covers write-once conflict, pointer CAS conflict, read, list, and delete
  through the routed `/minio/s3` edge. Remaining daemon work is acquiring this
  client from `BootConfig` / `LiveConfig` and using it inside the running
  service.
- `JitML.Service.PulsarWebSocketSubprocess` implements the routed one-shot
  `HasPulsar` publish/consume path against the running Pulsar HA cluster.
  Sprint `4.4` live validation covers broker WebSocket routing, topic creation,
  producer ack, consume, and WebSocket ack-on-consume. Remaining daemon work is
  acquiring this client or a long-lived replacement from `BootConfig` /
  `LiveConfig`, then preserving explicit post-dispatch ack/redelivery and seek
  semantics inside the service loop.
- `JitML.Service.HarborSubprocess` implements the `HasHarbor` instance
  through typed Docker/curl subprocesses and explicit `HarborSettings`.
  Sprint `4.1` live Linux CPU validation pushes/promotes, pulls, lists, and
  checks artifact existence against the running Harbor portal+registry. The
  remaining daemon work is wiring that client into the long-running service
  acquisition path after Sprint `4.1`'s host Docker HTTP-registry blocker is
  resolved.
- `JitML.Service.KubectlSubprocess` implements the `HasKubectl`
  instance through the typed `Subprocess` boundary against
  `./.build/jitml.kubeconfig`. The typed `Subprocess` boundary now
  carries an optional `subprocessStdin :: Maybe Text` payload
  (`subprocessWithStdin` smart constructor) that `kubectlApply` uses
  to pipe YAML into `kubectl apply -f -` without shelling out.
  Validated by `jitml-integration` with an explicit repo-local kubeconfig
  setting and stdin command-shape assertions. The stdin path is independently
  validated by a `cat`-based fixture in `jitml-integration`.
- Add integration coverage in `jitml-integration` (Sprint `12.2`) that
  exercises each capability class against the explicit live cluster path.

## Sprint 5.5: At-Least-Once Pulsar Consumer with Message-Hash Deduplication 🔄

**Status**: Active
**Implementation**: `src/JitML/Service/Consumer.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`

### Objective

Stand up the local event-id and de-duplication helpers for the target
at-least-once Pulsar consumer per doctrine `At-Least-Once Event Processing`.
Idempotency remains the consumer's responsibility; the typed `EventID`
deduplication key is the protobuf message hash and is opaque to the broker.

### Deliverables

- Current `eventIdFromPayload` derives a SHA-256 payload hash and
  `processAtLeastOnce` keeps first-seen event IDs in deterministic order.
- Target `Consumer` subscribes to the substrate-scoped command topics
  (`training.command.<mode>`, `tune.command.<mode>`, `rl.command.<mode>`,
  `inference.request.<mode>`, plus `inference.command.apple-silicon` on the
  host daemon).
- Target `EventID` is the doctrine-typed deduplication key, derived from the protobuf
  message hash. The daemon does not trust client-supplied IDs.
- Target dispatcher routes by event kind to the per-domain handler (training,
  tune, RL, inference). Per-handler `dedupCache :: TVar (LRUSet EventID)`
  provides at-least-once → effectively-once for the duration the entry stays
  cached. Cache size and TTL are `LiveConfig` knobs.
- Acks are explicit; failure to ack within the `RetryPolicy` budget surfaces
  `AppError PulsarFailed`.

### Validation

1. `cabal test jitml-daemon-lifecycle` verifies identical payloads produce
   the same event id.
2. `processAtLeastOnce` collapses repeated event ids in deterministic order.
3. Live validation (target): the daemon's `Consumer` subscribes to the
   substrate-scoped command topics on a real Pulsar broker, dispatches
   each event by kind to the per-domain handler, populates the per-handler
   LRU dedup cache, acks each event explicitly, and treats Pulsar
   redeliveries of the same `EventID` as no-ops.

### Remaining Work

- `JitML.Service.Consumer` now exposes the typed dispatcher surface:
  `EventDomain` enumerates the four per-handler buckets (`TrainingDomain`,
  `TuneDomain`, `RlDomain`, `InferenceDomain`); `domainFor` pure-routes
  a topic name to its domain; `DedupCache` carries the bounded LRU
  list with `dedupCacheLimit`, `dedupCacheKnown`,
  `dedupCacheInsert`; `HandlerRouter` aggregates the four
  per-domain caches; `routeByKind` returns the updated router and a
  fresh-event flag in one step.
- `JitML.Service.Consumer.{consumerStep,runConsumerLoop,ConsumerOutcome}`
  implement the typed live Consumer IO loop. `consumerStep` walks one
  envelope: computes the payload-hash `EventID`, routes by topic
  prefix to the per-domain `HandlerRouter` cache, dispatches when
  fresh (via a caller-supplied `EventDomain -> EventId -> Text -> m
  (Either ServiceError ())` action), and acks only after successful dispatch;
  dedup hits are acked as idempotent no-ops through
  `HasPulsar.pulsarAcknowledge`. `runConsumerLoop` drains the
  subscription cursor for a budgeted N envelopes. Validated by
  `jitml-daemon-lifecycle` against a synthetic `HasPulsar` instance:
  4 deliveries with one duplicate produce 3 `ConsumerDispatched` +
  1 `ConsumerDeduplicated` outcomes and 4 acks; the standalone one-shot live
  Pulsar publish/consume path is validated by Sprint `4.4`, while this sprint
  still owns the daemon's long-lived redelivery/dedup path.
- `JitML.Service.Runtime.daemonTensorBoardDispatcher` is the first concrete
  dispatcher side effect: it routes rendered `CheckpointDone` payloads through
  `JitML.Observability.TbSidecar.dispatchCheckpointPayload` and returns a typed
  `ServiceError` if the sidecar write fails before ack. Filesystem-backed
  `jitml-integration` coverage validates this Phase `4.6` side effect.
- Ack failure surfacing `AppError PulsarFailed` is now exposed via
  `JitML.Service.Consumer.consumerOutcomeError`, which maps a
  `ConsumerError serviceErr` through `serviceErrorToAppError`. A
  `SETimeout` / `SETransient` from the ack path becomes
  `PulsarFailed`; clean `ConsumerDispatched` / `ConsumerDeduplicated`
  outcomes return `Nothing`. Validated via `jitml-daemon-lifecycle`.
  The lifecycle exit path is wired through
  `JitML.Service.Runtime.consumerLoopExit :: [ConsumerOutcome] ->
  Maybe AppError`, which walks the outcome batch via `asum . fmap
  consumerOutcomeError` and surfaces the first `AppError`. Validated
  by `jitml-daemon-lifecycle` against a clean batch (returns
  `Nothing`) and a poisoned batch with a `SETimeout` mid-stream
  (returns `Just (PulsarFailed "timeout: ack budget exhausted")`).
- Add integration coverage in `jitml-daemon-lifecycle` (Sprint `12.7`)
  exercising real redelivery + dedup against live Pulsar through the explicit
  live validation path.

## Sprint 5.6: Stateless `Deployment`, Pod Anti-Affinity, Per-Substrate Dhall 🔄

**Status**: Active
**Implementation**: `chart/templates/deployment-jitml-service.yaml`,
`src/JitML/Service/ConfigMap.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`,
`documents/engineering/cluster_topology.md`

### Objective

Land the stateless `Deployment` shape with pod anti-affinity at `topologyKey:
kubernetes.io/hostname`, plus bootstrap-rendered per-substrate Dhall configs.

### Deliverables

- `Deployment/jitml-service` with `replicas: 1` default, pod anti-affinity at
  hostname topology so the cluster can scale to N replicas without colliding
  per node. **Not** a `StatefulSet` — durable state lives entirely in MinIO
  and Pulsar.
- `runtimeClassName: nvidia` only when substrate is `linux-cuda`.
- `jitml bootstrap --<substrate>` renders
  `./.build/conf/cluster/<substrate>.dhall` and
  `chart/templates/configmap-jitml-service.yaml`; live deployment into a
  ConfigMap mounted into `jitml-service` remains target apply behavior.
- The cluster Dhall declares `residency = Cluster`, `inferenceMode =
  SelfInference` for Linux substrates, and `ForwardToHost` for Apple.
- `jitml bootstrap --apple-silicon` also renders
  `./.build/conf/host/apple-silicon.dhall`; target live bootstrap patches the
  chosen edge port so the host daemon can reach Pulsar and MinIO.
- Linux substrates do not render a host-level Dhall file; all JIT operations
  happen in the cluster and the daemon knows that from its ConfigMap Dhall.
- Deployment template mounts `./.build/` from the worker hostPath into the
  pod at `/opt/build/` so the JIT cache is shared.
- `chart/templates/deployment-jitml-demo.yaml` is the sibling Deployment for
  the demo executable shim; Phase `11` owns the current frontend/demo scaffold
  and target HTTP server behavior.

### Validation

1. `chart/templates/deployment-jitml-service.yaml` renders the stateless
   Deployment surface.
2. `jitml bootstrap --<substrate>` materializes the service ConfigMap and
   Dhall files.
3. Live validation (target): the single-replica Deployment remains Ready
   through the live bootstrap path, scaling to multiple replicas honours pod
   anti-affinity by placing each replica on a distinct hostname, and the Apple
   host daemon subscribes to `inference.command.apple-silicon` after the edge
   port is leased.

### Remaining Work

- Validate the `topologyKey: kubernetes.io/hostname` anti-affinity by
  scaling to two replicas on a two-worker Kind cluster.
- Validate that the Apple host Dhall patched by Sprint `3.5` after the
  edge-port lease lets the host daemon connect to Pulsar and MinIO and
  subscribe live.
- Confirm `runtimeClassName: nvidia` is set only for `linux-cuda` and that
  the resulting pod actually sees the GPU on a GPU-labelled worker.

## Doctrine Sections Cited

- [../HASKELL_CLI_TOOL.md → Long-Running Daemons in the Same Binary](../HASKELL_CLI_TOOL.md) (every sprint)
- [../HASKELL_CLI_TOOL.md → Application Environment](../HASKELL_CLI_TOOL.md) (Sprints 5.1, 5.4)
- [../HASKELL_CLI_TOOL.md → Plan / Apply](../HASKELL_CLI_TOOL.md) (Sprint 5.1)
- [../HASKELL_CLI_TOOL.md → Capability Classes and Service Errors](../HASKELL_CLI_TOOL.md) (Sprint 5.4 — current service-error mapping and capability-class boundaries)
- [../HASKELL_CLI_TOOL.md → Retry Policy as First-Class Values](../HASKELL_CLI_TOOL.md) (Sprint 5.4)
- [../HASKELL_CLI_TOOL.md → At-Least-Once Event Processing](../HASKELL_CLI_TOOL.md) (Sprint 5.5)
- [../HASKELL_CLI_TOOL.md → Architecture → Subprocesses as Typed Values](../HASKELL_CLI_TOOL.md) (Sprint 5.4)
- [../HASKELL_CLI_TOOL.md → Error Handling](../HASKELL_CLI_TOOL.md) (Sprint 5.3)

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
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)

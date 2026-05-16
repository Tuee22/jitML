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
> rendering — while keeping live Pulsar/MinIO/Harbor clients explicit as target
> runtime validation.

## Phase Status

✅ **Done** for the local daemon configuration, lifecycle, endpoint, retry,
logging, at-least-once deduplication, hot-reload decision, capability-class, and
Deployment-rendering surfaces. The target daemon subscribes to Pulsar, persists
to MinIO, pulls images from Harbor, and reports metrics via the Prometheus stack
in live validation.

### Current Implementation Scope

The current worktree implements `BootConfig` / `LiveConfig` ADTs and Dhall
renderers, lifecycle phase data, hot-reload decision data, pure endpoint-response
rendering, pure JSON log rendering, service error/retry helpers, payload-hash
deduplication, capability-class definitions, and chart ConfigMap/Deployment
rendering, the POSIX signal/control surface in `src/JitML/Service/Signal.hs`,
and the low-level in-binary HTTP runtime in
`src/JitML/Service/{Http,Runtime}.hs` serving `/healthz`, `/readyz`, and
`/metrics`. `SIGHUP` increments the reload generation; `SIGINT` and `SIGTERM`
begin graceful drain and drop readiness. It does not yet implement real
MinIO/Pulsar/Harbor/kubectl clients or a live Pulsar consumer loop.

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

## Sprint 5.4: `RetryPolicy` and Service Error Surface ✅

**Status**: Done
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
3. Target integration coverage exercises `putBlobIfAbsent` against MinIO and
   asserts `If-None-Match: *` `412` is treated as success.

## Sprint 5.5: At-Least-Once Pulsar Consumer with Message-Hash Deduplication ✅

**Status**: Done
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

1. `cabal test jitml-daemon-lifecycle` verifies identical payloads produce the
   same event id.
2. `processAtLeastOnce` collapses repeated event ids in deterministic order.
3. Live Pulsar redelivery and MinIO side-effect validation remain target work.

## Sprint 5.6: Stateless `Deployment`, Pod Anti-Affinity, Per-Substrate Dhall ✅

**Status**: Done
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
2. `jitml bootstrap --<substrate>` materializes the local service ConfigMap and
   Dhall files.
3. Live `kubectl get deployment`, scale, and Apple host-daemon subscription
   validation remain target work.

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

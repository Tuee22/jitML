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

> **Purpose**: Stand up the `jitml service` long-running daemon — the single
> Pulsar-subscribed worker, parameterised entirely by Dhall `BootConfig` /
> `LiveConfig`, with mandatory SIGHUP hot reload, the `/healthz` / `/readyz` /
> `/metrics` endpoints, structured JSON stderr logging, recoverable-vs-fatal
> error kinds, the typed capability classes (`HasMinIO`, `HasPulsar`,
> `HasHarbor`, `HasKubectl`), the typed `RetryPolicy`, at-least-once Pulsar
> consumer semantics, and the stateless `Deployment` shape with pod anti-
> affinity.

## Phase Status

⏸️ **Blocked** on Phase `4` closure. The daemon subscribes to Pulsar, persists
to MinIO, pulls images from Harbor, and reports metrics via the Prometheus
stack — all established by Phase `4`.

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

## Sprint 5.1: `jitml service` Entry Point and `App.daemonMain` ⏸️

**Status**: Blocked
**Blocked by**: phase-4
**Implementation**: `src/JitML/Service/Service.hs`,
`src/JitML/Service/Lifecycle.hs`, `src/JitML/CLI/Commands/Service.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`

### Objective

Wire `jitml service` into the CLI as a long-running command with the
`Lifecycle: load → prereq → acquire → ready → serve → drain → exit` shape per
doctrine.

### Deliverables

- `jitml service [--config path/to/config.dhall]` is a Plan/Apply command;
  startup-as-plan supports `--dry-run` and `--plan-file` (renders the
  reconciliation plan, exits `0` without subscribing).
- `App.daemonMain :: BootConfig -> IO ExitCode` is the composition root.
- `Lifecycle` ADT enumerates the six phases; transitions log structured JSON
  events on stderr.
- Default config path resolution: `--config <path>` →
  `$JITML_SERVICE_CONFIG` →
  `./conf/<residency>/<substrate>.dhall`.

### Validation

1. `jitml service --dry-run --config conf/cluster/linux-cpu.dhall` prints the
   typed plan and exits `0` without side effects.
2. `jitml service` from inside the cluster pod reaches `Ready` per the
   structured log stream within 30 s.

## Sprint 5.2: `BootConfig` / `LiveConfig` Dhall and SIGHUP Hot Reload ⏸️

**Status**: Blocked
**Blocked by**: 5.1
**Implementation**: `src/JitML/Service/BootConfig.hs`,
`src/JitML/Service/LiveConfig.hs`, `src/JitML/Service/Reload.hs`,
`dhall/service/{BootConfig,LiveConfig}.dhall`
**Docs to update**: `documents/engineering/daemon_architecture.md`

### Objective

Split the daemon configuration into `BootConfig` (start-time only, restart-
required) and `LiveConfig` (hot-reloadable on SIGHUP), each backed by a Dhall
schema.

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
- SIGHUP triggers `LiveConfig` re-read; restart-required field changes (i.e.,
  any `BootConfig` field) emit `AppError InvalidConfig` with the structured
  diagnostic and exit `2` so the orchestrator restarts the pod.
- The Dhall schemas at `dhall/service/{BootConfig,LiveConfig}.dhall` are
  authoritative; Haskell decoders use `Dhall.input`.

### Validation

1. SIGHUP on a running daemon re-applies `LiveConfig` changes (e.g.,
   `logLevel`) without restart.
2. Editing a `BootConfig` field and SIGHUP-ing emits `AppError InvalidConfig`
   with the offending field name.
3. The Dhall schema round-trips through `dhall freeze` without diff.

## Sprint 5.3: `/healthz` / `/readyz` / `/metrics` and Structured Logging ⏸️

**Status**: Blocked
**Blocked by**: 5.1
**Implementation**: `src/JitML/Service/Endpoints.hs`,
`src/JitML/Service/Logger.hs`, `src/JitML/Service/Errors.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`

### Objective

Expose the doctrine-mandatory daemon endpoints and the structured JSON stderr
logger; classify errors as recoverable vs fatal.

### Deliverables

- `/healthz` returns `200 OK` if the daemon process is alive; `500` otherwise.
- `/readyz` returns `200 OK` only after the `Ready` lifecycle phase
  (capability classes acquired, prerequisite reconcile passed, Pulsar
  consumer subscribed); `503` otherwise.
- `/metrics` exposes Prometheus format scraped by the kube-prometheus-stack
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

1. `curl http://<pod-ip>:<healthz-port>/healthz` returns `200`; `/readyz`
   returns `503` during `Acquire` and `200` after `Ready`.
2. `curl http://<pod-ip>:<metrics-port>/metrics` is scraped by Prometheus and
   the metrics show in Grafana.
3. Synthetic recoverable errors are retried; synthetic fatal errors exit `2`
   with a structured diagnostic.

## Sprint 5.4: Capability Classes and `RetryPolicy` ⏸️

**Status**: Blocked
**Blocked by**: 5.1
**Implementation**: `src/JitML/Service/Caps/MinIO.hs`,
`src/JitML/Service/Caps/Pulsar.hs`, `src/JitML/Service/Caps/Harbor.hs`,
`src/JitML/Service/Caps/Kubectl.hs`,
`src/JitML/Service/Retry.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`

### Objective

Stand up the typed capability classes (`HasMinIO`, `HasPulsar`, `HasHarbor`,
`HasKubectl`) per doctrine `Capability Classes and Service Errors`, plus the
typed `RetryPolicy` per `Retry Policy as First-Class Values`. The capability
classes are the only allowed entry into external services from the daemon.

### Deliverables

- `class HasMinIO env where ...` exposes `putBlobIfAbsent`, `casPointer`,
  `getObject`, `listPrefix` per
  [../README.md → Concurrency model](../README.md#concurrency-model). The
  in-`Env` instance routes through the `minio-hs` client; mock instance for
  `jitml-unit`.
- `class HasPulsar env where ...` exposes `subscribe`, `produce`, `ack`,
  `seek`. The in-`Env` instance routes through `pulsar-client-haskell`.
- `class HasHarbor env where ...` exposes `pushImage`, `getImage`,
  `deleteImage`.
- `class HasKubectl env where ...` exposes `applyManifest`, `getResource`,
  `deleteResource`. All routed through the typed `Subprocess` boundary
  (Sprint `1.6`).
- `RetryPolicy` ADT with named strategies (`Once`, `LinearN k delayMs`,
  `ExponentialN k baseMs cap`, `RetryUntil deadline`). `retryServiceAction
  :: RetryPolicy -> (env -> IO a) -> env -> IO (Either AppError a)` is the
  single retry harness.
- Service-error kinds: `SEConflict` (retryable; from `If-Match`/`If-None-
  Match` `412`), `SEUnauthorized` (fatal), `SETimeout` (retryable per
  policy), `SETransient` (retryable per policy).

### Validation

1. `jitml-unit` exercises `retryServiceAction` against a synthetic
   `SEConflict`-emitting capability and asserts the policy is honoured.
2. `jitml-integration` exercises `putBlobIfAbsent` against MinIO and asserts
   `If-None-Match: *` `412` is treated as success.

## Sprint 5.5: At-Least-Once Pulsar Consumer with Message-Hash Deduplication ⏸️

**Status**: Blocked
**Blocked by**: 5.4
**Implementation**: `src/JitML/Service/Consumer.hs`,
`src/JitML/Service/EventId.hs`, `src/JitML/Service/Dispatch.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`

### Objective

Stand up the at-least-once Pulsar consumer per doctrine `At-Least-Once Event
Processing`. Idempotency is the consumer's responsibility; the typed `EventID`
deduplication key is the protobuf message hash and is opaque to the broker.

### Deliverables

- `Consumer` subscribes to the substrate-scoped command topics
  (`training.command.<mode>`, `tune.command.<mode>`, `rl.command.<mode>`,
  `inference.request.<mode>`, plus `inference.command.apple-silicon` on the
  host daemon).
- `EventID` is the doctrine-typed deduplication key, derived from the protobuf
  message hash. The daemon does not trust client-supplied IDs.
- The dispatcher routes by event kind to the per-domain handler (training,
  tune, RL, inference). Per-handler `dedupCache :: TVar (LRUSet EventID)`
  provides at-least-once → effectively-once for the duration the entry stays
  cached. Cache size and TTL are `LiveConfig` knobs.
- Acks are explicit; failure to ack within the `RetryPolicy` budget surfaces
  `AppError PulsarFailed`.

### Validation

1. Replaying the same Pulsar message twice produces one durable side effect
   (golden against MinIO writes).
2. A synthetic broker disconnect during `serve` triggers reconnect under the
   `RetryPolicy` and resumes consumption from the last acked offset.

## Sprint 5.6: Stateless `Deployment`, Pod Anti-Affinity, Per-Substrate Dhall ⏸️

**Status**: Blocked
**Blocked by**: 5.5, 4.7
**Implementation**: `chart/templates/deployment-jitml-service.yaml`,
`src/JitML/Bootstrap/Dhall.hs`, `src/JitML/Service/ConfigMap.hs`
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
  `./.build/conf/cluster/<substrate>.dhall` and deploys it as a ConfigMap
  mounted into `jitml-service`.
- The cluster Dhall declares `residency = Cluster`, `inferenceMode =
  SelfInference` for Linux substrates, and `ForwardToHost` for Apple.
- `jitml bootstrap --apple-silicon` also renders
  `./.build/conf/host/apple-silicon.dhall`, then patches it after the edge port
  is chosen so the host daemon can reach Pulsar and MinIO.
- Linux substrates do not render a host-level Dhall file; all JIT operations
  happen in the cluster and the daemon knows that from its ConfigMap Dhall.
- Deployment template mounts `./.build/` from the worker hostPath into the
  pod at `/opt/build/` so the JIT cache is shared.
- `chart/templates/deployment-jitml-demo.yaml` is the sibling Deployment for
  the demo HTTP server (Phase `11` populates the bundle; this sprint owns
  only the chart shape).

### Validation

1. `kubectl get deployment -n platform jitml-service` shows `Available` after
   `jitml bootstrap --<substrate>`.
2. `kubectl scale deployment jitml-service --replicas=2` lands two pods on
   distinct nodes.
3. The Apple Silicon host-native daemon launched by
   `jitml bootstrap --apple-silicon` reads
   `./.build/conf/host/apple-silicon.dhall` and subscribes to
   `inference.command.apple-silicon`.

## Doctrine Sections Cited

- [../HASKELL_CLI_TOOL.md → Long-Running Daemons in the Same Binary](../HASKELL_CLI_TOOL.md) (every sprint)
- [../HASKELL_CLI_TOOL.md → Application Environment](../HASKELL_CLI_TOOL.md) (Sprints 5.1, 5.4)
- [../HASKELL_CLI_TOOL.md → Plan / Apply](../HASKELL_CLI_TOOL.md) (Sprint 5.1)
- [../HASKELL_CLI_TOOL.md → Capability Classes and Service Errors](../HASKELL_CLI_TOOL.md) (Sprint 5.4)
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

- `system-components.md → jitml service Daemon Surface` rows move from
  `⏸️ Blocked` through `🔄 Active` to `✅ Done`.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)

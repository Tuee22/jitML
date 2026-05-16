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
lives in MinIO and Pulsar exclusively. Pod anti-affinity at `topologyKey:
kubernetes.io/hostname` allows multi-replica deployments to place at most one
pod per node. See [cluster_topology.md → `jitml-service` Deployment, Not
StatefulSet](cluster_topology.md#jitml-service-deployment-not-statefulset).

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
| `harborRegistry` | `Text` | Harbor registry FQDN |
| `httpListener` | `Optional HttpListener` | None when `residency = Host` |

`LiveConfig` (hot-reloadable on SIGHUP):

| Field | Type | Purpose |
|-------|------|---------|
| `logLevel` | `LogLevel` | `Debug \| Info \| Warn \| Error` |
| `retryPolicy` | `RetryPolicy` | Typed retry strategy |
| `tartIdleTimeout` | `Optional Natural` | Apple host-native only; default `1800` s |
| `inferenceBatchSize` | `Natural` | Per-batch inference budget |
| `inferenceMaxLatencyMillis` | `Natural` | Inference SLO |
| `drainDeadlineSeconds` | `Natural` | Graceful shutdown budget before forced exit |

The Dhall schemas at `dhall/service/{BootConfig,LiveConfig}.dhall` are present
for the current surface. Target Haskell decoders use `Dhall.input`.

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
| `/healthz` | Target HTTP endpoint; current renderable response value |
| `/readyz` | Target HTTP endpoint; current renderable response value |
| `/metrics` | Target Prometheus endpoint; current renderable text |

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
| `HasMinIO` | `minioPutIfAbsent`, `minioReadObject` | `src/JitML/Service/Capabilities.hs` |
| `HasPulsar` | `pulsarPublish`, `pulsarAcknowledge` | `src/JitML/Service/Capabilities.hs` |
| `HasHarbor` | `harborImageExists`, `harborPromoteImage` | `src/JitML/Service/Capabilities.hs` |
| `HasKubectl` | `kubectlApply`, `kubectlStatus` | `src/JitML/Service/Capabilities.hs` |

`HasKubectl` operations route through the typed `Subprocess` boundary
(`kubectl` is a wrapped subprocess).

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

## At-Least-Once Pulsar Consumer

Per doctrine `At-Least-Once Event Processing`. Idempotency is the consumer's
responsibility; the typed `EventID` deduplication key is derived from the
protobuf message hash and is opaque to the broker.

- `EventID` is derived from the protobuf message hash. The daemon does not
  trust client-supplied IDs.
- Per-handler `dedupCache :: TVar (LRUSet EventID)` provides at-least-once
  → effectively-once for the duration the entry stays cached. Cache size
  and TTL are `LiveConfig` knobs.
- Acks are explicit; failure to ack within the `RetryPolicy` budget surfaces
  `AppError PulsarFailed`.

The current consumer surface is the payload-hash deduplication helper. Target
consumer wiring subscribes to the substrate-scoped command topics (training,
tune, RL, inference, plus `inference.command.apple-silicon` on the host daemon).

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

Target `jitml bootstrap --apple-silicon` writes the cluster publication to
`./.build/runtime/cluster-publication.json`, patches
`./.build/conf/host/apple-silicon.dhall` with the routed Pulsar and MinIO
coordinates, then starts the host daemon from that Dhall. Linux has no
host-level Dhall; all JIT operations happen inside the cluster daemon.

The current implementation renders the configs, topic names, lifecycle,
deployment surfaces, and local HTTP endpoint server; live host daemon startup
and Pulsar/MinIO flow remain target runtime validation.

The host daemon's startup path never touches tart. On a JIT cache miss the
daemon first validates or installs the `tart` Homebrew package through typed
lazy prerequisite remediation, then calls `JitML.Tart.ensureVmUp jitml-build`,
which is idempotent.

Direct k8s API access from the host is hlint-forbidden.

## Generated Daemon Surface Table

<!-- jitml:daemon.surface:start -->
| Surface | Current owner | Current behavior |
|---------|---------------|------------------|
| `/healthz` | `JitML.Service.Runtime.daemonHttpRoutes` | Served by the in-binary HTTP runtime as a `200` response body |
| `/readyz` | `JitML.Service.Runtime.daemonHttpRoutes` | Served by the in-binary HTTP runtime with ready/not-ready status |
| `/metrics` | `JitML.Service.Runtime.daemonHttpRoutes` | Served by the in-binary HTTP runtime as Prometheus text |
| `BootConfig` | `JitML.Service.BootConfig` and `dhall/service/BootConfig.dhall` | Cluster/host residency, inference mode, Pulsar, MinIO, Harbor, HTTP listener fields |
| `LiveConfig` | `JitML.Service.LiveConfig` and `dhall/service/LiveConfig.dhall` | Log level, retry policy, tart idle timeout, inference batching/SLO, drain deadline fields |
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

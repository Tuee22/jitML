# Phase 57: `RetryPolicy` and Service Error Surface

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: RetryPolicy and Service Error Surface. Single-session phase migrated from legacy Sprint 5.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 57.1: `RetryPolicy` and Service Error Surface [✅ Done]

**Status**: Done
**Historical API note**: The method-level split Pulsar acquisition/consume/ack
surface below records the Sprint `5.4` closure at that date. Sprint `5.18`
supersedes it with opaque typed subscriptions and
`HasPulsar.pulsarConsumeUntil`; the retained MinIO/Harbor/kubectl and retry
surfaces remain current.
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
  :: RetryPolicy -> (env -> IO (Either ServiceError a)) -> env -> IO (Either
  AppError a)` is the pure retry harness.
- Service-error kinds: `SEConflict` (retryable; from `If-Match`/`If-None-
  Match` `412`), `SEUnauthorized` (fatal), `SETimeout` (retryable per
  policy), `SETransient` (retryable per policy).
- `HasMinIO`, `HasPulsar`, `HasHarbor`, and `HasKubectl` define the typed
  action boundaries used by later live service clients.
- `JitML.Service.Clients` closes client acquisition over the daemon role:
  Engine receives the MinIO/Pulsar-only `EngineServiceClient`, Coordinator
  receives the all-capability `DaemonServiceClient` backed by
  `DaemonClientSettings`, and Webapp receives no service client.
- `JitML.Service.Workload` provides the local typed runner for mutating
  daemon effects: checkpoint blob write, checkpoint pointer CAS, Harbor image
  promotion, kubectl apply/status/delete, and RunInference result publication.
- `JitML.Service.Runtime.daemonWorkloadDispatcher` parses rendered
  byte-faithful `WorkloadEffect` payloads and routes them through that runner
  before the consumer ack path returns success.
- On Linux lanes, the same dispatcher maps the current text `StartTraining` / `StopTraining`,
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
6. Historical pre-Sprint-`5.18` `jitml-daemon-lifecycle` validation verified
   the split subscription-acquisition boundary and recorded acquisition status.
   The current runtime instead derives the same typed subscription plan and
   obtains connection evidence from each persistent `pulsarConsumeUntil`
   session before readiness can be constructed.
7. `jitml-daemon-lifecycle` verifies the closed role projection: Engine uses
   the MinIO/Pulsar-only `EngineServiceClient`, Coordinator uses the
   all-capability `DaemonServiceClient`, and Webapp receives no service-client
   settings.
8. `jitml-daemon-lifecycle` verifies the role-specific runtime probes:
   `probeEngineServiceClients` crosses only the MinIO boundary, while
   `probeCoordinatorServiceClients` invokes MinIO list, Harbor list, and
   `kubectl get pods` exactly once each and records `client_probe_status` in
   the daemon summary.
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

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

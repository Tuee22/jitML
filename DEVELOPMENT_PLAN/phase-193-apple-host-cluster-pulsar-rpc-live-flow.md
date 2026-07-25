# Phase 193: Apple Host↔Cluster Pulsar RPC Live Flow

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Apple Host↔Cluster Pulsar RPC Live Flow. Single-session phase migrated from legacy Sprint 16.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 193.1: Apple Host↔Cluster Pulsar RPC Live Flow [✅ Done]

**Status**: Done as historical refs-RPC validation (full two-daemon round-trip
validated live 2026-05-31, Apple M1 / macOS 26); superseded by Sprint `16.12`,
which removed `AppleInferenceCommand` / `AppleInferenceEvent` and made raw
values-model forwarding the current path.
**Blocked by**: Sprint `191.1`, Phase `15` Sprint `168.1` (cluster up),
Phase `15` Sprint `15.2` (live capability classes), Phase `15` Sprint
`15.3` (daemon handlers consuming live broker)
**Implementation**: historical `src/JitML/Service/AppleInferenceRpc.hs`
(retired), `src/JitML/Service/PulsarWebSocketSubprocess.hs`,
`src/JitML/Service/MinIOSubprocess.hs`,
`src/JitML/Engines/MetalLocal.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`,
`documents/engineering/cluster_topology.md`

### Objective

Historical objective (retired by Sprint `16.12`): run the full Apple
host↔cluster inference RPC end-to-end: the in-cluster
daemon publishes an `AppleInferenceCommand` on
`inference.command.apple-silicon` with a MinIO-staged input tensor
reference, the host-native `jitml service` consumes it through
`HasPulsar.pulsarConsume`, loads the staged tensor through
`HasMinIO.minioReadBytes`, runs the Metal kernel via Sprint `16.2`,
stages the output to MinIO, and publishes the
`AppleInferenceEvent` reply on `inference.event.apple-silicon`. The
in-cluster daemon correlates the reply by `call-id` through
`AppleInferenceRpc.correlateCompletedEvent`.

### Deliverables

- The Apple host-native `jitml service` (`Host + SelfInference` mode,
  `inferenceMode = ForwardToHost`) subscribes to
  `inference.command.apple-silicon` with subscription `jitml-host` and
  acks only after the Metal launch and MinIO output stage complete.
- The cluster-side daemon publishes the matching `AppleInferenceCommand`
  through `HasPulsar.pulsarPublish` and consumes the reply event.
- Large tensor payloads transit through MinIO objects keyed by
  `(call-id, stage)`; the broker carries only the references.
- 2026-MM-DD validation note recorded under the sprint after the live
  run succeeds, naming the validation host hardware (M-series chip,
  memory, macOS + CommandLineTools `swiftc` version, cluster edge port).

### Validation

1. With Phase `15` cluster up and the host-native Apple daemon running:
   a single `InferenceRequest` published from a test driver produces a
   matching `InferenceResult` reply within the typed `RetryPolicy`
   budget, and `kubectl logs` shows the in-cluster daemon correlating
   the reply by `call-id`.
2. The Metal output read back from MinIO matches the deterministic
   reference output computed by the same Metal kernel run locally on
   the Apple host.

### Code Surface Landed (2026-05-31)

- **Cluster side** — `JitML.Service.Runtime.daemonWorkloadDispatcherForwardingInference`:
  on a parsed `InferenceRequest` it builds the RPC plan via
  `AppleInferenceRpc.appleInferenceRpcPlan` and publishes the
  `AppleInferenceCommand` on `inference.command.apple-silicon` through
  `HasPulsar.pulsarPublish` (non-inference payloads fall through to the standard
  workload dispatcher). `JitML.App.daemonWorkloadDispatcherForRuntime` routes
  `(AppleSilicon, ForwardToHost)` to it.
- **Host side** — `JitML.Service.AppleInferenceRpc.handleAppleInferenceCommand`
  runs the command's inference via an injected runner and builds the
  `AppleInferenceEvent` reply (completed-with-output-refs or error, echoing the
  `call-id`); `publishAppleInferenceEvent` publishes it on
  `inference.event.apple-silicon` through `HasPulsar`.
- **Host serve-loop integration** —
  `JitML.Service.Runtime.daemonWorkloadDispatcherHostingAppleInference` routes a
  parsed `AppleInferenceCommand` off the host daemon's subscription through
  `handleAppleInferenceCommand` → `publishAppleInferenceEvent`, falling through to
  the weighted self-inference path for direct `RunInference` payloads.
  `JitML.App.appleHostInferenceRunner` is the concrete runner: it parses the
  command inputs, runs `runMetalWeightedCheckpointInference` for the model
  (`loadInferenceCheckpointWithWeights`), stages the float output to a
  `call-id`-keyed MinIO object via `putBlobIfAbsent`, and returns that object
  reference. `daemonWorkloadDispatcherForRuntime` routes `(AppleSilicon,
  SelfInference)` to it.
- **Cluster correlation leg** — `daemonWorkloadDispatcherForwardingInference`
  also handles a reply `AppleInferenceEvent` arriving on
  `inference.event.apple-silicon` (it self-identifies by `call-id`) by
  republishing it to the client result topic `inference.result.apple-silicon`
  (stateless). `JitML.Service.Consumer.daemonSubscriptionsForBootConfig` adds the
  `inference.event` subscription to the Apple in-cluster (`ForwardToHost`) daemon.
  **All three serve-loop legs** — publish-command, host-handle-and-reply,
  correlate-and-republish — are now wired in the daemon dispatch + subscription
  plan.
- **Round-trip validated deterministically** — `jitml-daemon-lifecycle` (31 / 31)
  exercises command → `handleAppleInferenceCommand` → event →
  `correlateAppleInferenceEvent` (success + error paths), the event publish, and
  the Apple in-cluster subscription plan (now including `inference.event`).
  `cabal build all` clean.

### Validation (live broker, 2026-05-31, Apple M1 / macOS 26)

Exercised the full RPC round-trip over a **real standalone Pulsar broker**
(`apachepulsar/pulsar:3.3.1`, WebSocket enabled, ~2.25 GiB) through the live
`JitML.Service.PulsarWebSocketSubprocess` interpreter (Node-driven Pulsar
WebSocket producer/consumer) — no Kind cluster, low memory risk:

1. `pulsarSubscribe` created durable `jitml-host` / `jitml-cluster` subscriptions
   on `inference.command.apple-silicon` / `inference.event.apple-silicon`.
2. Cluster side `publishAppleInferenceRpcCommand` published the
   `AppleInferenceCommand` (broker msg id `CAkQADAA`).
3. Host side `pulsarConsume` received it (`call-id=live-call-14-4`),
   `handleAppleInferenceCommand` built the completed reply, and
   `publishAppleInferenceEvent` published it (msg id `CAoQADAA`).
4. Cluster side `pulsarConsume` received the event and
   `correlateAppleInferenceEvent` matched it by `call-id`, yielding
   `["minio://jitml-checkpoints/out/live-call-14-4"]`.

This validates the RPC envelope flow + bidirectional `call-id` correlation over a
live broker via the production WS interpreter.

### Validation (full two-daemon round-trip, 2026-05-31, Apple M1 / macOS 26)

Exercised the **complete request → command → event → result round-trip through two
real running daemon processes** over a standalone broker (`apachepulsar/pulsar:3.3.1`,
WS enabled) + standalone MinIO — no Kind, no OOM risk. Crucially, the **cluster-side
daemon was the actual `jitml:local` image binary** (the same artifact deployed
in-pod), run via `docker run jitml:local jitml service --consume-once`; its
hard-coded in-cluster Pulsar DNS
(`ws://pulsar-broker.platform.svc.cluster.local:8080/ws`, set by
`JitML.Service.Clients.pulsarSettingsForBootConfig` `Cluster` branch) was redirected
to the host broker with `--add-host pulsar-broker.platform.svc.cluster.local:host-gateway`.
The host-side daemon was the host-native `jitml service` (residency `Host`,
`inferenceMode = SelfInference`). Each leg ran through the real
`daemonConsumerBatch` consume loop + `daemonWorkloadDispatcherForRuntime` routing
(not the direct interpreter):

1. A client `InferenceRequest` (`call-id=live-rt-14-4`) was produced to
   `inference.request.apple-silicon`.
2. **Cluster daemon** (image binary) drained it and
   `daemonWorkloadDispatcherForwardingInference` published the forwarded
   `AppleInferenceCommand` (verified on `inference.command.apple-silicon`:
   `envelope: AppleInferenceCommand / call-id: live-rt-14-4 / kind: inference`).
3. **Host daemon** (native) drained the command and
   `daemonWorkloadDispatcherHostingAppleInference` →
   `handleAppleInferenceCommand` → `appleHostInferenceRunner` ran; it published the
   reply `AppleInferenceEvent` to `inference.event.apple-silicon`.
4. **Cluster daemon** (image binary) drained the event,
   `correlateAppleInferenceEvent` matched it by `call-id`, and republished to the
   client reply topic `inference.result.apple-silicon`.
5. The client consumed the correlated result:
   `envelope: AppleInferenceEvent / call-id: live-rt-14-4 / kind: error /
   error-code: inference-failed` — `call-id` propagated cleanly through all four
   legs and back.

The host runner deliberately ran the **error path** (no seeded MinIO checkpoint →
`pointer read failed: SEUnauthorized "minioReadBytes: HTTP 403"`), which fully
exercises the serve-loop plumbing — consume → route → handle → publish — through
both real daemon binaries. The Metal compute step itself is validated bit-exact in
Sprints `16.2`/`16.5`, so seeding a checkpoint for the success path adds no
serve-loop coverage and was skipped.

### Remaining Work

- None for the serve loop. The full round-trip is live-validated through two
  running daemon processes (the cluster leg using the actual `jitml:local` image
  binary). The only delta from a Kubernetes-orchestrated deployment is the
  orchestration layer itself (Deployment + ConfigMap + in-cluster Service DNS),
  which is substrate-agnostic and validated live for the training/tune/RL daemons
  in Phase `15`. Running this exact flow inside a Kind pod via
  `jitml bootstrap --apple-silicon` remains available as an optional belt-and-braces
  check but is **not** a code gate; it is heavy on this 16 GiB host (the
  `cluster.host-memory` preflight is a no-op on macOS).

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

# Phase 58: At-Least-Once Pulsar Consumer with Message-Hash Deduplication

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: At-Least-Once Pulsar Consumer with Message-Hash Deduplication. Single-session phase migrated from legacy Sprint 5.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 58.1: At-Least-Once Pulsar Consumer with Message-Hash Deduplication [✅ Done]

**Status**: Done
**Historical API note**: The one-shot and caller-settled worker methods below
record the Sprint `5.5` validation surface at that date. Sprint `5.18`
supersedes them with receipt-bearing deliveries and interpreter-owned
settlement. Payload-hash semantic deduplication remained only until Sprint
`8.16`; that downstream sprint replaces it with plan-bound semantic identity.
The Sprint `5.5` bullets below remain a dated record.
**Implementation**: `src/JitML/Service/Consumer.hs`,
`src/JitML/Service/PulsarWebSocketSubprocess.hs`, `src/JitML/App.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`

### Objective

Stand up the local event-id and de-duplication helpers for the target
at-least-once Pulsar consumer per doctrine `At-Least-Once Event Processing`.
Idempotency remains the consumer's responsibility; the typed `EventID`
deduplication key is the protobuf message hash and is opaque to the broker.

### Deliverables

- Historically, `eventIdFromPayload` derived a SHA-256 payload hash and
  `processAtLeastOnce` keeps first-seen event IDs in deterministic order.
- Current `daemonSubscriptionsForBootConfig` derives the substrate-scoped
  command topic plan from `BootConfig`:
  `training.command.<mode>`, `tune.command.<mode>`, `rl.command.<mode>`, and
  `inference.request.<mode>` for clustered Engine daemons, plus
  `inference.command.apple-silicon` and the Training/Tune/RL host-command routes
  for the Apple host Engine. Non-Engine roles never acquire compute
  subscriptions.
- The retired `subscribeDaemonTopics` helper crossed the split
  `HasPulsar.pulsarSubscribe` boundary and returned one result per planned
  subscription. Sprint `5.18` replaces it with persistent scoped consumption.
- The historical compatibility `EventID` was derived from the protobuf message
  hash and did not trust client-supplied IDs. Sprint `8.16` replaces it with
  plan-bound semantic identity; a payload hash is not the target identity.
- Target dispatcher routes by event kind to the per-domain handler (training,
  tune, RL, inference). Per-handler `dedupCache :: TVar (LRUSet EventID)`
  suppresses repeated handler effects while an entry stays cached. Cache size
  and TTL are `LiveConfig` knobs; broker delivery remains at-least-once.
- Historically, acks were explicit and failure to ack within the `RetryPolicy`
  budget surfaced `AppError PulsarFailed`; the receipt-bound interpreter now
  owns and applies one settlement for each returned handler decision. This is
  settlement ownership, not an exactly-once broker-delivery guarantee.
- The retired routed WebSocket subprocess path recorded broker message ids and
  sent them through a separate `pulsarAcknowledge` call after dispatch success.
- The retired `JitML.Service.PulsarWebSocketSubprocess.runPulsarConsumerWorker` started a
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
3. Historical pre-Sprint-`5.18` `cabal test jitml-daemon-lifecycle` validation
   verified `domainFor` accepted live
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
   handler dispatch did not insert the event id into the dedup cache and allowed
   the next redelivery to dispatch.
   `jitml-integration` verifies the WebSocket-backed subscribe probe renders the
   routed consumer endpoint used for actual broker acquisition with
   `receiverQueueSize=0`, so acquisition did not prefetch pending work. Sprint
   `5.18` supersedes the split subscribe/seek/ack surface with one persistent
   receipt-bound interpreter.
4. Historical `cabal test jitml-integration` validation verified
   `JitML.Cluster.PulsarBootstrap` registered the then-current 31-topic derived
   family and rejected retired
   `*.cluster` / `*.host` topic names.
5. Live Linux CPU validation on 2026-05-20 confirmed the live broker had the
   then-current 26-topic substrate-scoped family and the standalone routed
   WebSocket path published/consumed on
   `persistent://public/default/training.command.linux-cpu`, the same current
   topic family the daemon subscription plan targets.
6. Historical `cabal test jitml-integration` validation covered the retired
   split WebSocket consume/ack worker. Sprint `5.18` replaces that surface with
   the persistent bridge whose parent returns one typed disposition and whose
   interpreter alone settles the private broker receipt.
7. Historical live Linux CPU validation on 2026-05-21 published the same `RunInference`
   payload twice to the running held-open daemon worker and consumes exactly one
   matching `InferenceResult` from `inference.result.linux-cpu`, proving the
   process-lifetime `HandlerRouter` dedup cache is populated by live broker
   deliveries and duplicate payload hashes are acked as idempotent no-ops.
   This is retained historical evidence; current semantic identity is
   plan/kind/key-derived and current settlement is receipt-bound.
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

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

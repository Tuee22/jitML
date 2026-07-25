# Phase 71: Receipt-Bound Delivery and Total Settlement

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Receipt-Bound Delivery and Total Settlement. Single-session phase migrated from legacy Sprint 5.18 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 71.1: Receipt-Bound Delivery and Total Settlement [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/App.hs`, `src/JitML/Service/{BootConfig,LiveConfig,Retry}.hs`,
`src/JitML/Service/Capabilities.hs`,
`src/JitML/Service/Pulsar/{Internal,Bridge}.hs`,
`src/JitML/Service/PulsarWebSocketSubprocess.hs`,
`src/JitML/Service/Consumer.hs`, `src/JitML/Service/Runtime.hs`,
`src/JitML/Service/RuntimeState.hs`, `src/JitML/Sub/Piped.hs`,
`src/JitML/Coordinator/Topology.hs`, `src/JitML/Proto/{Training,Tune,Rl,Inference,Gc}.hs`,
`src/JitML/Test/{PulsarBridge,PulsarTransport,RuntimeState,Workload}.hs`,
`test/daemon-lifecycle/{Main,SigtermRegression}.hs`, `test/integration/Main.hs`,
`test/unit/ProtocolCodec.hs`
**Docs to update**: `../README.md`,
`../documents/engineering/daemon_architecture.md`,
`../documents/engineering/pulsar_ml_workflow.md`,
`../documents/engineering/run_contract.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`,
`../documents/engineering/unit_testing_policy.md`

### Objective

Make broker delivery identity, decoding, and settlement one typed operation so
acknowledging the wrong delivery, acknowledging twice, or forgetting settlement
cannot be expressed by a handler. This sprint owns the daemon portion of
[Exit Definition](README.md#exit-definition) item `32`.
The binding design is
[README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- The validated Coordinator topology derives all 34 physical routes from 14
  logical names and exposes hidden-constructor `Topic event` and `Subscription
  event` values rather than raw topic/subscription identifiers.
- A persistent scoped `pulsarConsumeUntil` interpreter yields an opaque decoded
  `Delivery event` containing its broker receipt. A handler returns a
  `ConsumerDecision` carrying exactly one `Disposition`; the interpreter alone
  applies Ack or Nack, reconnects, drains, and cleans up owned resources.
- Broker message ids and the bounded live-receipt map remain private to the
  bridge. Payload/newline values are neither delivery identity nor a settlement
  key, and the public split consume/ack capability surface does not exist.
- Training, Tune, RL, Inference, and GC route decoders reject unknown,
  duplicate, malformed, missing, empty, non-finite, and cross-lane fields. The
  closed `DaemonCommand` value reaches dispatch and status projection without a
  second raw-payload parse.
- Non-empty kind-indexed workload programs pair every `WorkloadEffect kind`
  with only its legal result. Typed placement rejects consumed/requested lane
  disagreement and carries the handle required by each placement variant.
- Closed `Starting`, `Ready`, `Degraded`, and `Draining` daemon states carry
  readiness evidence. SIGTERM keeps `/readyz` observable as `503` while an
  in-flight handler completes and settles, then enforces the configured drain
  deadline before listener and worker cleanup.
- Piped consumer failures retain the exact structured process outcome and
  cleanup failure context without replacing the primary failure.
- BootConfig refinement rejects impossible residency/inference/role/listener
  combinations before runtime construction. Only Engine acquires compute
  subscriptions; Webapp runs under the shared signal scope; unsupported
  Coordinator startup fails closed.
- The adjacent operational LiveConfig loads before startup. Actual Engine and
  Webapp processes distinguish unchanged, valid changed, malformed-live, and
  immutable-Boot SIGHUP outcomes; active dedup bounds and shutdown use the
  atomic last-good snapshot. Unsupported no-op logging/retry/batching/SLO
  fields are absent until Sprint `12.16` supplies their readers.
- Apple Training/Tune/RL Stops fail closed and Nack at host and cluster
  boundaries without deleting a nonexistent Job, publishing false status, or
  marking dedup. Sprint `12.16` owns keyed host handles and successful Stops.
- Redelivery, equal payloads with distinct receipts, strict decode, handler and
  settlement failure, reconnect ordering, asynchronous drain, scoped ownership,
  receipt-table pruning, Apple stop routing, hot reload, configured drain
  deadlines, orphan-free forced cleanup, and actual Engine/Webapp signals are
  covered.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-daemon-lifecycle --linux-cpu
docker compose run --rm jitml jitml test jitml-integration --linux-cpu --test-options='-p !/ProductRow/'
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

The integration selector runs exactly **81** cases: all 62 non-ProductRow
cases plus all 19 Live cases. It excludes only the **56** downstream
`ProductRow integration matrix (Sprint 28.1)` cases (one coverage meta-case and
55 artifact-backed rows), which cannot acquire a backward dependency into this
strict-chain sprint. Phase `28` retains and must pass that 56-case gate; the
selector neither skips nor marks those cases passed.

Closure evidence (2026-07-12): `jitml-unit` passed **343 / 343**;
`jitml-daemon-lifecycle` passed **41 / 41**; the selector above passed **81 /
81** in **1184.07s**, including **19 / 19** Live cases. Focused diagnosis also
passed receipt-bound redelivery **1 / 1** and StartTraining placement/dedup **2
/ 2** on a clean broker. A fresh `linux-cpu` bootstrap executed **130** phased
steps, and both `jitml docs check` and `jitml check-code` returned success.

### Remaining Work

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

# Pulsar ML-Workflow Contract

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../../README.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/development_plan_standards.md, ../../DEVELOPMENT_PLAN/phase-262-contract-driven-live-execution-browser-and-playwright.md, run_contract.md, daemon_architecture.md
**Generated sections**: none

> **Purpose**: The shared normative cross-project contract, specialized locally
> by jitML and its `infernix` sister project, for ML workflows (training and
> inference) over Pulsar: the
> three-role split (Engine / Coordinator / Webapp), the derived topic algebra,
> the `Work*` envelope family, the artifact + readiness contract, the
> websocket snapshot/patch surface, and the coordination primitives. This is the
> converged target both projects adopt; each project records any current
> implementation gap and its owning forward sprint rather than claiming that a
> retained compatibility role already satisfies the target.

## Current Status

The shared coordination language is aligned with `infernix`: a Pulsar
`Failover` subscription means stable single-active broker coordination, not a
repository-owned high-availability guarantee. jitML's role split,
receipt-bound settlement, redelivery, and semantic dedup paths are implemented.
Its local Engine cardinality is still three in the checked-in renderer and will
be reduced to one by the reopened Phase 42 → Phase 53 → Phase 69 chain. See
[DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md#closure-status).

Positive multi-worker profiles remain supported. With the current `Failover`
Engine subscription they are active/standby, not `Shared` throughput workers;
jitML retains at-least-once semantics but no longer requires an explicit
multi-worker or node-failover acceptance lane.

## Why this contract exists

jitML (JIT-compiled, multi-substrate **training + inference**) and `infernix`
(Pulsar-driven model **inference serving**) are converging on one Pulsar-based
ML-workflow shape. This document is the authoritative, **project-neutral**
contract. The sibling lives at
`documents/architecture/pulsar_ml_workflow.md` in `infernix`; each repository
adds project-local detail for substrate identifiers, kernel codegen, topology,
and delivery mechanics. Changes to the shared role, envelope, or phasing
invariants require a synchronized sibling-project update. jitML-specific
receipt and evidence rules live in [Typed Run Contract](run_contract.md), not in
the shared invariant text.

## The three roles

One binary; the role is selected by the typed Dhall config it is given (no
separate per-role executables). Every role runs the same lifecycle skeleton —
`Load → Prereq → Acquire → Ready → Serve → Drain → Exit` — with role-specific
`acquire`/`serve`/`drain` callbacks.

| Role | Resides | Sole responsibility | Talks to |
|------|---------|---------------------|----------|
| **Engine** | cluster **or** host | ML **compute only** — training and inference; substrate/lane-specific JIT execution | **Pulsar + MinIO only** |
| **Coordinator** | cluster only | **Owns Pulsar topic lifecycle**; batching, fan-in/fan-out, routing; **readiness gating** (derivation/training completion → serveable) | Pulsar + MinIO + cluster API |
| **Webapp** | cluster | **Thin websocket server** for the browser; work dispatch + result/event streaming + static-artifact serving; **no ML compute** | **Pulsar + MinIO only** + browser (websocket) |

**jitML specialization.** The target Linux cluster runs one Engine replica for
inference compute and one non-compute Coordinator for Training/Tune/RL placement
and cluster orchestration. The Coordinator alone owns Harbor/kubectl probes and
the namespace-scoped Job/`pods/exec` RBAC; Engine retains only MinIO plus its
typed compute subscription. On `apple-silicon`, the cluster Engine Deployment
has zero replicas, the Coordinator forwards all four domains, and the host
Engine consumes inference plus Training/Tune/RL host commands. Webapp has no
compute subscription on any lane.

Invariants:

- The **Engine is the only role that computes.** No inference or training runs in
  the Webapp or Coordinator. (In jitML this retires the in-process demo inference
  and the triplicated load→runner→kernel path.)
- The **Webapp is substrate-agnostic.** It publishes work and renders results off
  Pulsar topics; it never knows whether Apple Metal, CUDA, or oneDNN computed the
  result. (This is why the Apple in-pod-Metal problem does not exist under this
  shape: the webapp publishes `inference.request.<lane>`; engine residency/forwarding
  is an internal Engine/Coordinator concern.)
- The **Coordinator owns topic lifecycle.** At acquire it creates or observes
  every topic derived from the validated topology, rejects duplicate, missing,
  or unexpected observations, and records opaque exact-family evidence before
  consumer connections can make readiness true. Topics are never hardcoded in
  a static list.

## Topic algebra

Every topic name is **derived** from a typed descriptor and a **validated routing
graph**; hand-written topic strings are forbidden.

```
topicFor :: Tenant -> Namespace -> Workflow -> Phase -> Lane -> TopicName
  Workflow = < Train | Infer | Tune | Rl | … >          -- project supplies its set
  Phase    = < Command | Event | Result | Batch >        -- Batch = coordinator→engine routing
  Lane     = project routing key                          -- jitML: substrate; infernix: (mode,pool,model)
```

The coordinator validates the routing graph (reject unroutable models / one-sided
pool↔member links) and reconciles the exact derived topic set at startup. A new
workflow or lane changes the descriptor, not a hand-edited topic list.

## The `Work*` envelope family

Training and inference are the **same** request → events → result shape,
correlated by `callId`:

```
WorkCommand { callId, workflow, lane, subjectRef, artifactRef?, payload, replyTopic }
WorkEvent   { callId, workflow, progress }   -- Train: epoch/loss; Infer: token/batch/none
WorkResult  { callId, status, outputRefs }   -- Train: checkpoint refs; Infer: output refs
```

- `subjectRef` is the durable subject a result routes back to (jitML: an
  experiment/run; infernix: a `(userId, contextId)` conversation).
- `artifactRef` (see below) is present when a workflow consumes a derived artifact
  (e.g. inference over a trained checkpoint).
- A project may leave a workflow unimplemented (`infernix` does not implement
  `Train`); the envelope family still represents it.

## Artifact + readiness contract

A **content-addressed MinIO artifact store** plus a **`.ready` sentinel written
last** is the cross-project mechanism that makes "use an underived artifact"
unrepresentable in the domain.

- A serveable `ArtifactRef` is obtainable **only** from a completed derivation:
  - jitML: a training `WorkResult` whose checkpoint manifest has `step ≥ 1` and a
    resolvable `latest` pointer → the coordinator writes the `ready` sentinel.
  - infernix: the coordinator's model-bootstrap downloads + stages weights, then
    writes `.ready` last.
- The Webapp and Coordinator reference an `ArtifactRef`, never a raw id.
- **Parse, don't validate, at the wire boundary.** A malformed command is always
  *possible* on the wire; the daemon parses it into a validated `ArtifactRef`/total
  domain value or emits a typed rejection event — never a silent bad state.

## Websocket surface (Webapp ↔ browser)

- Typed **snapshot + patch** frames. The browser applies patches mechanically; no
  business logic in the browser.
- Per-subject Pulsar **Readers**; **no session affinity** (any webapp pod serves
  any connection).
- Static artifacts (SPA bundle, uploads, result blobs) move via MinIO **presigned
  URLs**.
- Inference is therefore **asynchronous to the browser** like training/RL/tune
  already are: the panel publishes a request and renders the streamed result;
  it does not block on a synchronous compute response.

## Coordination primitives

- **Failover subscriptions** for every single-owner coordinator loop (dispatch,
  result-bridge, readiness/bootstrap): stable subscription name = ownership,
  process-qualified consumer name = consumer observability. This is stable
  single-active broker coordination, not standby-role availability or
  repo-owned HA. (`infernix`'s coordinator Failover loops are the shared
  reference.) jitML Engine consumers use the same subscription type, so an
  intentionally expanded Engine set is active/standby rather than shared-load
  compute.
- **Producer-side semantic dedup** keyed by `callId` is a pure first-seen fold
  over the work log. It makes duplicate commands idempotent at that semantic
  boundary; it does not change Pulsar's at-least-once delivery contract into an
  atomic or globally exactly-once broker guarantee.
- **Single-flight / batching** expressed as pure reducers over the work log
  (testable offline without a broker).

jitML specializes delivery settlement with opaque broker receipts and derives a
semantic `EventId` from the refined plan, command kind, and logical key; the two
identities never alias. Its inference consumer reads a positive batch-size and
latency snapshot at first admission, groups compatible `RunInference` requests
by experiment/checkpoint and input width, and retains every hidden receipt.
Collection closes on size/compatibility or at the sparse cutoff
`admission + min(1 ms, latency / 10)`; the distinct captured
handler/publication-entry deadline remains `admission + latency`. This sends an
under-capacity batch to Engine with most of its SLO intact without extending the
captured window.

Daemon dispatch commits semantic dedup state per command. A later cancellation
restores only that command's in-progress transition, so earlier successful
commands survive a whole-batch Nack and do not repeat their effects on
redelivery. If the handler does not return before timeout, the transport cancels
it and Nacks the admitted receipts. Engine refuses to enter a Pulsar publication
after the captured deadline. A decision that does return is never
retroactively Nacked by a later clock sample because publication may already be
externally visible; broker acknowledgement or publication completion is not
guaranteed by the deadline. Commanded and drain-race settlements must flush and
be confirmed before `Drained`.

The jitML inference CLI never computes. It **establishes** one `Owned`,
`FromLatest` reply cursor through an acknowledged admin subscription `CREATE`,
publishes the typed request to Engine, and waits for the correlated result only
when both `callId` and experiment hash match. Release cancels and
joins the short-lived consumer before a bounded, cancellation-safe subscription
`DELETE`.

Establishment precedes publication, and the types enforce that order. A
latest-position cursor is planted at the topic tail when the **broker** creates
the subscription, so a reply published before that creation sits permanently
behind the cursor and cannot be replayed; a socket-open lifecycle event is not
evidence that the cursor exists. The acknowledged `CREATE` is that evidence, and
it is the sole mint for an opaque `ReplyCursor`. The correlated publish takes
that token and reads the request topic and the reply-topic text out of it, so
neither "publish before the cursor exists" nor "publish a request naming a reply
topic the subscription does not cover" is expressible. Uncorrelated publishes —
those whose result is consumed by an independently established cursor, such as
the browser's own websocket bridge — remain ordinary publishes and are marked as
such at their call sites. Settlement, drain/protocol, bridge-process, and cleanup failures
observed during cancellation remain typed; only a fully successful drain and
cleanup rethrows the original asynchronous-cancellation identity. Product Tune
evidence likewise comes from the registered `ProductRow` and Catalog
schedule—TPE/ASHA/`MedianPruner`, `128` trials, seed `1729`, a `1000`-optimizer-
update ceiling allocated through eta-derived measured rungs, parallelism `1`,
target `1.0`, slack `0.05`—and a reduced
transport/lifecycle smoke cannot mint completion. See
[Typed Run Contract → Delivery and Settlement](run_contract.md#delivery-and-settlement).

## Configuration and roles

- One binary; `activeRole : Role = < Engine | Coordinator | Webapp >` plus
  per-role config is read from typed Dhall at startup (no env-var role selection).
- **Reflected Dhall schema**: the binary emits the schema its decoders accept
  (so the schema cannot drift from the types). This is the convention both repos
  adopt.
- Each role receives a separate ConfigMap, ServiceAccount, subscription plan,
  probe set, and capability profile. `service --consume-once` remains an
  Engine-only diagnostic and cannot be used to make Coordinator or Webapp
  inherit Engine dispatch.

## Phasing rules (both repos)

These two rules govern every phase in both repos' `DEVELOPMENT_PLAN/`:

1. **Forward-only DAG.** Every `Blocked by` / dependency edge references an
   equal-or-lower-numbered phase. No earlier phase is blocked by an incomplete
   later phase. The plan is workable strictly in numerical order.
2. **Single-accelerator per phase.** A phase that needs an accelerator validates on
   **exactly one** of `{apple-silicon, the GPU lane}` plus `linux-cpu` (which runs
   on both hardware sets and is the common lane). No phase's validation gate
   requires both accelerators. Cross-accelerator aggregation is a `linux-cpu`-only
   phase that merges committed per-lane attestations.

> The GPU lane is `linux-cuda` in jitML and `linux-gpu` in `infernix`; substrate
> identifiers stay per-repo and are not renamed.

## Conformance checklist

A project conforms to this contract when all hold:

- [ ] One binary; role ∈ `{Engine, Coordinator, Webapp}` selected by typed Dhall.
- [ ] Engine is the only role that computes; Webapp and Coordinator run no ML.
- [ ] Webapp is substrate-agnostic (talks to Pulsar + MinIO only).
- [ ] Coordinator owns explicit topic lifecycle; no implicit auto-create, no
      hardcoded topic list.
- [ ] Every topic is derived from the typed descriptor + validated routing graph.
- [ ] Training and inference use the `WorkCommand → WorkEvent* → WorkResult`
      family, correlated by `callId`.
- [ ] A serveable `ArtifactRef` is mintable only from a completed derivation; a
      `.ready` sentinel is written last.
- [ ] The browser receives snapshot + patch frames over websocket; inference is
      asynchronous to the browser.
- [ ] Failover subscriptions provide stable single-active coordination;
      acknowledgement ordering and semantic dedup make redelivery idempotent
      while broker delivery remains at-least-once, without claiming platform
      HA.
- [ ] The binary emits its own (reflected) Dhall schema.
- [ ] Every phase obeys forward-only DAG + single-accelerator-per-phase.

## Validation

jitML validates this contract on its target single-worker local profile. The
focused gates prove one default Engine, `Failover` subscription rendering,
at-least-once redelivery and deduplication, receipt-bound settlement, and total
drain. No conformance criterion requires multiple workers, `Shared`
subscriptions, or broker/node failover.

```bash
docker compose build jitml
docker compose run --rm jitml jitml test jitml-integration --linux-cpu \
  --test-options='-p local-topology'
docker compose run --rm jitml jitml test jitml-daemon-lifecycle --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

## Related Documents

- [README.md](README.md)
- [../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md)
- [../../DEVELOPMENT_PLAN/development_plan_standards.md](../../DEVELOPMENT_PLAN/development_plan_standards.md)
- [../../README.md](../../README.md)
- [run_contract.md](run_contract.md) — jitML-specific refinement, evidence,
  settlement, lifecycle, interpreter, and journal specialization

> Engineering docs that elaborate this contract's jitML-specific surfaces
> (`daemon_architecture.md`, `cluster_topology.md`, `training_workloads.md`,
> `checkpoint_format.md`, `purescript_frontend.md`) cross-reference it as the
> convergence work lands; the engineering suite map ([README.md](README.md)) lists it.

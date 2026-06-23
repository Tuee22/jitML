# Pulsar ML-Workflow Contract

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../../README.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/development_plan_standards.md
**Generated sections**: none

> **Purpose**: The cross-project contract — shared verbatim with the `infernix`
> sister project — for ML workflows (training and inference) over Pulsar: the
> three-role split (Engine / Coordinator / Webapp), the derived topic algebra,
> the `Work*` envelope family, the artifact + readiness contract, the
> websocket snapshot/patch surface, and the coordination primitives. jitML and
> `infernix` both implement this shape so the two projects stay convergent rather
> than diverging into two incompatible rewrites.

## Why this contract exists

jitML (JIT-compiled, multi-substrate **training + inference**) and `infernix`
(Pulsar-driven model **inference serving**) are converging on one Pulsar-based
ML-workflow shape. This document is the authoritative, **project-neutral**
contract; the identical text lives at `documents/architecture/pulsar_ml_workflow.md`
in `infernix`. Where a project specializes the contract, it does so only in the
project-specific surfaces noted inline (substrate identifiers, kernel codegen,
topic namespace), never by diverging from the role split, envelope family, or
phasing rules.

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

Invariants:

- The **Engine is the only role that computes.** No inference or training runs in
  the Webapp or Coordinator. (In jitML this retires the in-process demo inference
  and the triplicated load→runner→kernel path.)
- The **Webapp is substrate-agnostic.** It publishes work and renders results off
  Pulsar topics; it never knows whether Apple Metal, CUDA, or oneDNN computed the
  result. (This is why the Apple in-pod-Metal problem does not exist under this
  shape: the webapp publishes `inference.request.<lane>`; engine residency/forwarding
  is an internal Engine/Coordinator concern.)
- The **Coordinator owns topic lifecycle.** Topics are created/validated/torn down
  by the coordinator from a typed topology descriptor — never auto-created
  implicitly and never hardcoded in a static list.

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
  process-qualified consumer name = replica observability. HA with no external
  consensus system.
- **Producer-side broker dedup** keyed by `callId` → at-least-once becomes
  effectively-once; the dedup decision stays a pure fold over the work log.
- **Single-flight / batching** expressed as pure reducers over the work log
  (testable offline without a broker).

## Configuration and roles

- One binary; `activeRole : Role = < Engine | Coordinator | Webapp >` plus
  per-role config is read from typed Dhall at startup (no env-var role selection).
- **Reflected Dhall schema**: the binary emits the schema its decoders accept
  (so the schema cannot drift from the types). This is the convention both repos
  adopt.

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
- [ ] Failover subscriptions + producer dedup provide HA and effectively-once.
- [ ] The binary emits its own (reflected) Dhall schema.
- [ ] Every phase obeys forward-only DAG + single-accelerator-per-phase.

## Related Documents

- [README.md](README.md)
- [../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md)
- [../../DEVELOPMENT_PLAN/development_plan_standards.md](../../DEVELOPMENT_PLAN/development_plan_standards.md)
- [../../README.md](../../README.md)

> Engineering docs that elaborate this contract's jitML-specific surfaces
> (`daemon_architecture.md`, `cluster_topology.md`, `training_workloads.md`,
> `checkpoint_format.md`, `purescript_frontend.md`) cross-reference it as the
> convergence work lands; the engineering suite map ([README.md](README.md)) lists it.

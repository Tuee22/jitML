# Phase 67: One-Binary Engine / Coordinator / Webapp Role Model

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: One-Binary Engine / Coordinator / Webapp Role Model. Single-session phase migrated from legacy Sprint 5.14 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 67.1: One-Binary Engine / Coordinator / Webapp Role Model [✅ Done]

**Status**: Done (role model + lifecycle skeleton surface; live Coordinator
reconcile/readiness and multi-role serving owned by Sprint `12.16`)
**Depends-On**: Sprint `5.12` (reflected schema carries `activeRole`), Sprint
`5.13` (Coordinator role owns the topic algebra)
**Implementation**: `src/JitML/Service/RoleLifecycle.hs` (new),
`src/JitML/Service/BootConfig.hs` (`Role` + `bootActiveRole`),
`src/JitML/Service/Runtime.hs` (`active_role:` summary block),
`dhall/service/BootConfig.dhall`,
`chart/local/jitml-service/templates/configmap.yaml` (deployed `BootConfig.dhall`
carries `activeRole`), `test/daemon-lifecycle/Main.hs`
**Docs to update**: `../documents/engineering/daemon_architecture.md`,
`../documents/engineering/pulsar_ml_workflow.md`, `system-components.md`

### Objective

Make `jitml service` a **one-binary role model** — `activeRole : Role = < Engine |
Coordinator | Webapp >` selected by typed Dhall — run through one shared
**role-lifecycle skeleton** `Load → Prereq → Acquire → Ready → Serve → Drain →
Exit` with role-specific `acquire`/`serve`/`drain` callbacks. Implements `The
three roles` + `Configuration and roles` of
[../documents/engineering/pulsar_ml_workflow.md](../documents/engineering/pulsar_ml_workflow.md).
Adopts `Long-Running Daemons in the Same Binary` and `Application Environment`
from [../README.md](../README.md).

### Deliverables

- Add `Role = Engine | Coordinator | Webapp` to the reflected `BootConfig`
  (Sprint `5.12`); no env-var role selection.
- Add `JitML.Service.RoleLifecycle` with the shared skeleton and the typed
  per-role callback record. The **Engine** is the only role that computes
  (training + inference); the **Coordinator** owns topic lifecycle (Sprint `5.13`)
  + readiness gating; the **Webapp** is a thin websocket/static surface (live
  serving owned by Phase `11`).
- Route the existing daemon serve path through the Engine callbacks so current
  Linux/Apple behaviour is preserved under `activeRole = Engine`.

### Validation

- `docker compose run --rm jitml jitml test jitml-daemon-lifecycle --linux-cpu`
  covers: each role selects its capability profile; the lifecycle skeleton runs the
  phase order for every role; `activeRole = Engine` is the BootConfig default and
  the only compute role.
- Live multi-role rollout (Coordinator pod + Engine pod(s) + Webapp pod) is owned
  downstream by Sprint `12.16`; this sprint closes on the offline skeleton +
  role-selection proof per standards rule M(b).
- `docker compose run --rm jitml jitml docs check` and `jitml check-code`.

### Validation State (host-native, apple-silicon lane)

- **Landed and validated host-native.** `Role = Engine | Coordinator | Webapp` is
  a first-class typed-Dhall field on `BootConfig` (`activeRole`, reflected into the
  schema by Sprint `5.12`, defaulting to `Engine`). `JitML.Service.RoleLifecycle`
  layers the per-role capability profile (`profileComputes` / `profileOwnsTopics`
  / `profileServesWebsocket`) onto the existing shared lifecycle skeleton
  (`JitML.Service.Lifecycle`, `Load → … → Exit`), and the daemon runtime summary
  now renders an `active_role:` block. `jitml-daemon-lifecycle` passes **35 / 35**
  with a new case asserting exactly the Engine computes, every role shares the
  skeleton/phase order, and `BootConfig` defaults to `Engine`.
- **Live `linux-cpu` validation.** On a freshly bootstrapped `linux-cpu` Kind
  cluster, `deployment/jitml-service` rolls out `1/1 Running` decoding the
  convergence `BootConfig` (with `activeRole`) and reaches `readyz: ready`; the
  daemon log shows it acquired the **topic-algebra-derived** subscriptions
  (`persistent://public/default/{rl.command,inference.request}.linux-cpu` — exactly
  `JitML.Coordinator.Topology.topicFor` output, Sprint `5.13`). The live lane
  caught a real regression the static gates missed — the hand-written
  `chart/local/jitml-service/templates/configmap.yaml` deployed a `BootConfig.dhall`
  without `activeRole`, crash-looping the daemon on the now-required field; fixed by
  adding `activeRole = < Engine | Coordinator | Webapp >.Engine` to that template.
  After the fix a clean `jitml bootstrap --linux-cpu` completes all **84** rollout
  steps (publication written), and `jitml test jitml-integration --linux-cpu`
  passes **71 / 71** (incl. the `Live` group: WorkflowMatrix dispatch over the
  derived topics, live PPO/cartpole convergence through daemon dispatch, inference
  round-trip through `engineWeightedInference`, MinIO/Pulsar/Harbor round-trips) —
  so the Phase `5` (and Phase `10.7` `engineWeightedInference`) convergence
  refactors are behavior-preserving and live-correct on `linux-cpu`.

### Remaining Work

None. The retained role model is complete: Engine computes, Webapp serves
without constructing an Engine runtime, and the unsupported Coordinator fails
closed. Live Coordinator acquire/serve/drain reconciliation is an explicit
downstream ownership transfer to Sprint `12.16`, not Sprint `5.14` Remaining
Work.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

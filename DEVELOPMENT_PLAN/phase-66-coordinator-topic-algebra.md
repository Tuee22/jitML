# Phase 66: Coordinator Topic Algebra

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Coordinator Topic Algebra. Single-session phase migrated from legacy Sprint 5.13 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 66.1: Coordinator Topic Algebra [✅ Done]

**Status**: Done (derived topic algebra surface; live coordinator reconcile owned
by Phase `15`)
**Implementation**: `src/JitML/Coordinator/Topology.hs` (new),
`src/JitML/Cluster/PulsarBootstrap.hs` (hardcoded literals removed; sources the
derived set), `test/unit/Main.hs`, `test/integration/Main.hs` (topic-family
assertion now over the derived set), `src/JitML/Bootstrap.hs`,
`src/JitML/Service/Runtime.hs`
**Docs to update**: `../documents/engineering/cluster_topology.md`,
`../documents/engineering/daemon_architecture.md`,
`../documents/engineering/pulsar_ml_workflow.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Give the **Coordinator** role explicit Pulsar **topic-lifecycle ownership** and
**derive every topic name** from a typed topology descriptor plus a validated
routing graph, retiring the hardcoded `PulsarBootstrap` topic list created inline
during `bootstrap`. Implements the `Topic algebra` section of
[../documents/engineering/pulsar_ml_workflow.md](../documents/engineering/pulsar_ml_workflow.md)
and the "Hardcoded Pulsar topic list" ledger row. Adopts `Reconcilers: Idempotent
Mutation as a Single Command` and `Subprocesses as Typed Values` from
[../README.md](../README.md).

### Deliverables

- Add `JitML.Coordinator.Topology` with a typed descriptor and the derivation
  `topicFor :: Tenant -> Namespace -> Workflow -> Phase -> Lane -> TopicName`,
  where `Workflow = Train | Tune | Rl | Infer | Gc`, `Phase = Command | Event |
  Result | Request | HostCommand`, and `Lane = Substrate`. The derived set must
  equal the current 9×3 substrate family plus the Apple-only internal/host-command
  topics (31 total; no string drift).
- Validate the routing graph: reject unroutable workflow/lane pairs and one-sided
  command↔event links; the coordinator reconciles the exact derived topic set at
  startup (idempotent create, 409-tolerant) instead of `bootstrap` walking a
  hand-written list.
- Delete `pulsarTopics` / `substrateTopics` / `appleSiliconInternalTopics` and the
  inline creation in `src/JitML/Bootstrap.hs`; the bootstrap rollout calls the
  coordinator's reconcile entrypoint.
- Move the "Hardcoded Pulsar topic list" ledger row to `Completed` after the
  derived-set parity test is green.

### Validation

- `jitml test jitml-unit --linux-cpu` (or `--apple-silicon`) covers: derived
  topic set ≡ the previously hardcoded family; routing-graph validator rejects an
  unroutable descriptor; reconcile plan is idempotent.
- `docker compose run --rm jitml jitml test jitml-daemon-lifecycle --linux-cpu`
  (subscription plan still derived from the same descriptor).
- Live coordinator topic reconcile during `jitml bootstrap --linux-cpu` is owned
  downstream by Phase `15` (`linux-cpu` lane on this host) — this sprint closes on
  the offline derived-set/routing-graph proof per standards rule M(b).
- `docker compose run --rm jitml jitml docs check` and `jitml check-code`.

### Validation State (host-native, apple-silicon lane)

- **Landed and validated host-native.** `JitML.Coordinator.Topology` defines the
  typed descriptor (`Workflow`, `Phase`, `RouteEntry`, `jitmlTopology`), the
  contract's `topicFor`, the validated routing graph (`validateTopology` rejects
  duplicates, empty lanes, and one-sided command/report links), and the derived
  `coordinatorTopics`. `JitML.Cluster.PulsarBootstrap` no longer contains any
  hardcoded topic literals (`substrateTopics` / `appleSiliconInternalTopics` /
  the literal `pulsarTopics` were deleted); it sources the family from
  `coordinatorTopics` and keeps only the typed `pulsar-admin topics create`
  mechanics.
- `cabal build lib:jitml` and `cabal build jitml-integration` compile
  warning-clean. `cabal run jitml-unit` passes **202 / 202** (two new cases: the
  derived family has the expected topic members, and
  `validateTopology jitmlTopology = Right ()` while a command-only entry is
  rejected). The offline `jitml-integration` "registers the substrate-scoped topic
  family (Sprint 5.5)" case still passes over the derived set.
- **Daemon subscription plan repointed.** `daemonSubscriptionsForBootConfig`
  (`JitML.Service.Consumer`) now derives every subscription topic through
  `Topology.topicFor` (typed `Workflow`/`Phase`/`Substrate`) instead of ad-hoc
  string prefixes, producing byte-identical topic names — `jitml-daemon-lifecycle`
  stays **35 / 35**.

### Remaining Work

- Repoint the `jitml bootstrap` rollout's topic-create step at the `Topology`
  descriptor's reconcile entrypoint (it already runs over the derived
  `coordinatorTopics` via `runPulsarTopicCreatesIO`; the explicit
  Coordinator-role reconcile-at-startup is the live piece owned by Sprint
  `12.16`).
- Run the container `jitml docs check` / `jitml check-code` gate, align
  `cluster_topology.md`, and move the "Hardcoded Pulsar topic list" ledger row to
  `Completed` (the live coordinator reconcile is owned by Sprint `12.16`).

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

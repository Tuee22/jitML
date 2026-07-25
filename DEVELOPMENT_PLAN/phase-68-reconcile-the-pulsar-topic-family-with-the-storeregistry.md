# Phase 68: Reconcile the Pulsar Topic Family with the `StoreRegistry`

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Reconcile the Pulsar Topic Family with the StoreRegistry. Single-session phase migrated from legacy Sprint 5.15 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 68.1: Reconcile the Pulsar Topic Family with the `StoreRegistry` [✅ Done]

**Status**: Done (reopened 2026-06-23; re-closed 2026-06-24) — unblocked by Phase 2
Sprint `2.15` and Phase 4 Sprint `4.9`.

Make the durable-state registry the single declared source for the logical Pulsar
topic family, and hold `JitML.Coordinator.Topology` consistent with it:

- The registry (`JitML.Project.Config.defaultProjectConfig`) declares the 13 logical
  `MessageTopic` names (`training.command`/`event`, `tune.*`, `rl.*`,
  `inference.request`/`result`/`command`, `gc.event`, and the three `*.host-command`
  legs).
- New `JitML.Coordinator.Topology.topologyLogicalNames` projects `jitmlTopology` to
  its distinct substrate-stripped `workflow.phase` names; a `jitml-unit` anti-drift
  test asserts the registry's `MessageTopic` set equals it, so the per-substrate
  routing cannot diverge from the declared family.

Note (granularity): the registry declares the *logical* family; `jitmlTopology` owns
the *per-substrate* expansion (the routing graph + `validateTopology`). Sprint `5.15`
reconciles the two — one declared source, anti-drift-checked — rather than deleting
the per-substrate routing, which is load-bearing.

### Exit Definition

- The registry's `MessageTopic` logical-name set equals
  `topologyLogicalNames jitmlTopology` (anti-drift test green); the registry is the
  single declared source for the topic family.

### Validation State (2026-06-24)

- `cabal build lib:jitml` clean (`Coordinator.Topology` + `Project.Config` recompile).
- `jitml-unit` **218/218**, incl. "registry MessageTopic names mirror the Coordinator
  topology logical family".

### Remaining Work

- None on the topic source-of-truth surface. Folding the daemon's reflected
  `BootConfig`/subscription schema onto the same registry types is a follow-on; the
  topic *family* is now registry-declared + anti-drift-checked.
- Documentation Requirements: **met (2026-06-24)** — `daemon_architecture.md` notes the
  logical topic family is registry-declared and anti-drift-checked (`topologyLogicalNames`),
  cross-linking `durable_state_dsl.md`; the README durable-state registry note covers the
  Pulsar topic prose.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

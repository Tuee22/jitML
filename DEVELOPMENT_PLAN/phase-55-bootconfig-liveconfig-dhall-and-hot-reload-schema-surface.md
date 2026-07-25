# Phase 55: `BootConfig` / `LiveConfig` Dhall and Hot-Reload Schema Surface

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: BootConfig / LiveConfig Dhall and Hot-Reload Schema Surface. Single-session phase migrated from legacy Sprint 5.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 55.1: `BootConfig` / `LiveConfig` Dhall and Hot-Reload Schema Surface [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Service/BootConfig.hs`,
`src/JitML/Service/LiveConfig.hs`,
`src/JitML/Service/HotReload.hs`,
`dhall/service/{BootConfig,LiveConfig}.dhall`
**Docs to update**: `documents/engineering/daemon_architecture.md`

### Objective

Split the daemon configuration into current `BootConfig` / `LiveConfig` ADTs,
Dhall schema files, renderers, and the local SIGHUP reload-decision surface.

### Deliverables

- `BootConfig` carries:
  - `substrate : Substrate`
  - `residency : Cluster | Host`
  - `inferenceMode : SelfInference | ForwardToHost`
  - `pulsarServiceUrl`, `pulsarAdminUrl`, `minioEndpoint`, `harborRegistry`
    (when `residency = Host`, bootstrap writes these into
    `./.build/conf/host/apple-silicon.dhall` from
    `./.build/runtime/cluster-publication.json`)
  - `httpListener : Maybe HttpListener` (none when `residency = Host`)
- `LiveConfig` carries:
  - `dedupCacheSize`, `dedupCacheTtlSeconds`
  - `drainDeadlineSeconds`
- LiveConfig contains only operational hot fields. Dynamic log filtering,
  service retry, inference batching, and latency-SLO control are owned by Sprint
  `12.16`; Phase `5` does not accept inert fields and report them as applied.
- `JitML.Service.HotReload` models the local reload snapshot and SIGHUP reload
  decision: unchanged `LiveConfig` is ignored, changed `LiveConfig` increments
  the generation.
- `JitML.Service.Signal` wires POSIX `SIGHUP`, `SIGINT`, and `SIGTERM` into the
  daemon control surface. SIGHUP rereads both configs, ignores unchanged or
  malformed LiveConfig while retaining the last-good snapshot, and increments
  generation only after a valid changed LiveConfig is atomically applied.
  Reloaded dedup bounds reconfigure live routers and the latest drain deadline
  governs shutdown. Any changed or malformed BootConfig is restart-required:
  readiness drops, work drains, and `AppError InvalidConfig` asks the
  orchestrator to restart. `SIGINT` / `SIGTERM` begin the same graceful drain.
- The Dhall schemas at `dhall/service/{BootConfig,LiveConfig}.dhall` are
  present and match the renderers; the `BootConfig` loader uses `Dhall.inputFile`
  and rejects unknown substrate text before building the daemon runtime.

### Validation

1. `jitml service` renders the current BootConfig and LiveConfig summaries.
2. `dhall/service/BootConfig.dhall` and `dhall/service/LiveConfig.dhall`
   exist and match the current renderer vocabulary; `jitml-integration`
   round-trips a rendered cluster `BootConfig` through `loadBootConfig`.
   `jitml-integration` also verifies the checked-in service ConfigMap carries
   the current `LiveConfig` fields including `dedupCacheSize` and
   `dedupCacheTtlSeconds`.
3. `jitml-unit` exercises the pure reload decision and checked Natural-to-Int
   configuration boundary.
4. `jitml-daemon-lifecycle` exercises signal-to-action mapping, atomic
   generation changes, live router resize/TTL pruning, and an actual compiled
   service across unchanged, changed, malformed-live, and restart-required
   BootConfig SIGHUP cases.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

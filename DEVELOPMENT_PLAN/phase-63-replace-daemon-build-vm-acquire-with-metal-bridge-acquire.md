# Phase 63: Replace daemon build-VM acquire with Metal bridge acquire

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Replace daemon build-VM acquire with Metal bridge acquire. Single-session phase migrated from legacy Sprint 5.10 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 63.1: Replace daemon build-VM acquire with Metal bridge acquire [✅ Done]

**Status**: Done (2026-06-12)
**Implementation**: `src/JitML/Service/LiveConfig.hs`,
`dhall/service/LiveConfig.dhall`, `chart/templates/configmap-jitml-service.yaml`,
`src/JitML/App.hs`, `src/JitML/Service/Runtime.hs`,
`src/JitML/Prerequisite/Nodes/Container.hs`, `src/JitML/Engines/MetalRuntime.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`, `documents/engineering/determinism_contract.md`, `system-components.md`

### Objective

Remove the VM lifecycle from `jitml service` startup and make the Apple host
daemon acquire only the fixed Metal bridge and OS Metal runtime. Adopts
`Long-running daemons in the same binary`, `Application Environment`, and
`Capability classes and service errors` from [../README.md](../README.md).

### Deliverables

- Remove `buildVmCpu`, `buildVmMemoryMib`, `buildVmDiskGib`, and
  `buildVmIdleTimeout` from `LiveConfig` and Dhall renderers.
- Delete `ensureHostBuildVm` from `runService` acquire; replace it with a
  fail-closed `ensureAppleMetalBridge` / `metalRuntimeAvailable` check on
  `AppleSilicon + SelfInference`.
- Surface bridge/runtime acquisition status in the daemon startup summary and
  convert failures to typed `AppError` / service-error output before subscribing
  to work.
- Move the daemon build-VM ledger row to `Completed` after validation.

### Validation

- `jitml-unit` Dhall/LiveConfig round-trips pass with no build-VM fields.
- `jitml-daemon-lifecycle` covers successful and failed fixed-bridge acquisition.
- On Apple Silicon, `jitml service --config ./.build/conf/host/apple-silicon.dhall --consume-once 0`
  invokes no `tart` subprocess and reports the bridge/runtime acquisition.

### Validation State (2026-06-12)

- Host build gate: `cabal build lib:jitml test:jitml-unit
  test:jitml-daemon-lifecycle` passed.
- Host daemon tests: `cabal test jitml-unit jitml-daemon-lifecycle` passed
  `jitml-unit` 197 / 197 and `jitml-daemon-lifecycle` 33 / 33.
- Apple host fail-closed smoke: with a temporary host config and a stub
  `system_profiler` reporting `Metal: Supported` but no fixed bridge dylib,
  `cabal run exe:jitml -- service --config "$cfg" --consume-once 0` exited `2`,
  rendered `apple_metal_acquire:` with
  `failed apple.metal-runtime=yes apple.metal-bridge=no`, reported
  `prerequisite unmet: apple.metal-bridge`, and did not invoke the temporary
  `tart` stub or print `build-vm`.
- Container code-quality/build gate: `docker compose build jitml` passed with
  `check-code: ok` plus the PureScript bundle build.
- Container validation lane:
  `docker compose run --rm jitml jitml test jitml-unit --linux-cpu` passed
  197 / 197,
  `docker compose run --rm jitml jitml test jitml-daemon-lifecycle --linux-cpu`
  passed 33 / 33, and
  `docker compose run --rm jitml cabal test jitml-integration
  --test-options="-p !/Live/"` passed 49 / 49.
- Chart regression after removing the stale checked-in ConfigMap fields:
  `docker compose run --rm jitml sh -lc 'cabal --builddir=/tmp/jitml-phase5-chart-test test jitml-integration --test-options="-p \"jitml-service local chart carries current Dhall config surface\""'`
  passed 1 / 1. The direct no-`--builddir` retry failed first because Cabal
  picked up a stale mounted `dist-newstyle`, so the isolated build directory is
  the recorded validation.
- Final docs/whitespace gates: `docker compose run --rm jitml jitml docs check`
  passed and `git diff --check` passed.
- Direct host `cabal test jitml-integration --test-options='-p !/Live/'` is not
  the supported validation lane on this Mac host and failed at the generated
  Linux CPU oneDNN compile because the host lacks `oneapi/dnnl/dnnl.hpp`; the
  container lane above is the authoritative code-quality/test lane per
  `AGENTS.md`.

### Remaining Work

None. The daemon no longer owns a build VM or idle timeout. Remaining Tart /
SwiftPM generated-cache-miss residue belongs to Phase `7` Sprint `7.11`, and
Apple live validation belongs to Phase `16` Sprint `16.9`. The later Apple
host-residency placement defect is owned by Sprint `5.11`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

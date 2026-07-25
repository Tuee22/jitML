# Phase 61: Retire Tart VM Lifecycle from the Daemon

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Retire Tart VM Lifecycle from the Daemon. Single-session phase migrated from legacy Sprint 5.8 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 61.1: Retire Tart VM Lifecycle from the Daemon [✅ Done]

**Status**: Done (2026-05-30)
**Implementation**: `dhall/service/LiveConfig.dhall`,
`src/JitML/Service/LiveConfig.hs`, `src/JitML/App.hs` (daemon `acquire`
lifecycle), `src/JitML/Service/Runtime.hs`
**Docs to update**: `../documents/engineering/daemon_architecture.md`

### Objective

With the Apple Metal build moving to a host CommandLineTools `swift build` +
runtime `MTLDevice.makeLibrary(source:)` (Phase `7` Sprint `7.8`), the daemon no
longer provisions or manages a Tart VM. Remove `LiveConfig.tartIdleTimeout` and
the Tart spin-up step from the `acquire` lifecycle. Adopts `Long-Running Daemons
in the Same Binary` and `Application Environment` from [../README.md](../README.md).

### Deliverables

- `LiveConfig.tartIdleTimeout` removed from `dhall/service/LiveConfig.dhall` and
  the Haskell `LiveConfig` record + the generated `daemon.surface` table.
- The Apple-host `acquire` step no longer validates/installs `tart` or spins a VM
  up; the first Apple JIT cache miss simply runs the host `swift build` through
  the typed `Subprocess` boundary.
- Removal tracked in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

### Validation

1. `cabal build all` clean; `cabal test jitml-unit` green (LiveConfig
   round-trip + daemon-surface golden updated).
2. `grep -rn "tartIdleTimeout" src dhall chart` returns nothing after closure;
   governed docs keep only historical removal notes.

### Remaining Work

- None. Landed 2026-05-30: `tartIdleTimeout` removed from
  `dhall/service/LiveConfig.dhall`, the `LiveConfig` Haskell record + renderer,
  and the `daemon.surface` generated table; the daemon `acquire` step has no Tart
  spin-up (the first Apple cache miss runs the host `swift build`). 30
  `jitml-daemon-lifecycle` + 183 `jitml-unit` pass; `cabal build all` clean.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

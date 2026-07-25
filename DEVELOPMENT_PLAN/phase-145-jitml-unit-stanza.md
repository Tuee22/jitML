# Phase 145: `jitml-unit` Stanza

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: jitml-unit Stanza. Single-session phase migrated from legacy Sprint 12.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 145.1: `jitml-unit` Stanza [✅ Done]

**Status**: Done
**Implementation**: `test/unit/`, `jitml.cabal` (the `jitml-unit` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`

### Objective

Keep `jitml-unit` as the unit workload covering parser, generated
docs, prerequisite, environment, AppError, Plan/Subprocess, bootstrap-script,
runtime-source, and cache surfaces. Broader per-domain snapshot suites
(restricted to pure-renderer output per [../README.md → Snapshot
targets → Numerical-fixture
prohibition](../README.md#snapshot-targets)) are owned by the relevant
domain-specific stanzas rather than this unit-stanza sprint.

### Deliverables

- `test/unit/Main.hs` runs the current `tasty` tree.
- The current body covers command registry/parser/help/json, generated-doc
  checks, env resolution, plan rendering, subprocess rendering and fixture
  execution, prerequisite topology/remediation, bootstrap script diagnostics,
  cache-key/layout/manifest/symlink behavior, runtime-source determinism, and
  AppError rendering.
- Current pure-renderer snapshot fixtures live under `test/snapshots/cache/`,
  `test/snapshots/cli/`, and `test/snapshots/prerequisite/`. The legacy
  `test/golden/` tree is scheduled for deletion per
  [legacy-tracking-for-deletion.md → Pending Removal](legacy-tracking-for-deletion.md#pending-removal)
  and a `jitml lint files` rule (added in this sprint) fails any new
  file under that path.
- Route-table and Grafana daemon-health renderer snapshots are present
  under `test/snapshots/`. RL and AlphaZero per-game correctness is
  asserted through run-to-run determinism plus rule-conformance
  property tests; no per-substrate trajectory or transcript files are
  committed per [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets). The numerical and RL
  Dhall catalog mirrors are audited by the unit/lint body.

### Validation

1. `cabal test jitml-unit` exits `0` for the body.
2. Existing snapshot fixtures (pure-renderer output only) are
   deterministic and contain no timestamps or random identifiers.
3. `jitml lint files` fails if any file is committed under
   `test/golden/`, per [../README.md → Snapshot targets →
   Numerical-fixture prohibition](../README.md#snapshot-targets).

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

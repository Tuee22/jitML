# Phase 146: `jitml-integration` Stanza (Subprocess Boundary + Determinism)

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: jitml-integration Stanza (Subprocess Boundary + Determinism). Single-session phase migrated from legacy Sprint 12.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 146.1: `jitml-integration` Stanza (Subprocess Boundary + Determinism) [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface only. Live HTTP MinIO
checkpoint round-trip migrated to Phase `15` Sprint `15.7`. The
per-substrate determinism assertion against real CUDA and Metal
production kernels migrated to Phase `17` Sprint `17.1`.
**Implementation**: `test/integration/`,
`jitml.cabal` (the `jitml-integration` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`

### Objective

Keep `jitml-integration` as the integration workload for the typed
subprocess boundary, renderer surfaces, real-binary spawn matrix, and
filesystem-backed capability coverage; grow live service effects and
same-substrate training determinism per `### Remaining Work` below.

### Deliverables

- `test/integration/Main.hs` runs the current `tasty` tree.
- The current body exercises `runStreaming` against `/bin/echo`.
- It verifies the local bootstrap plan includes the Harbor-first publication
  ordering.
- It verifies Kind config rendering is deterministic and route registry
  rendering covers the registered routes.
- It compares the rendered route table against
  `test/snapshots/cluster/route-table.md` (pure-renderer snapshot per
  [../README.md → Snapshot targets](../README.md#snapshot-targets)).
- Real `jitml` binary spawning is now exercised by the
  `spawned ./.build/jitml binary matrix against a real workdir` test —
  it locates the dist-newstyle binary, spawns it through the typed
  `Subprocess` boundary in a temporary workdir, and asserts the
  expected dry-run / help / no-op behaviours for `--help`, `bootstrap`,
  `cluster up`, `internal gc`, `service --help`, `train --dry-run`, and
  the Sprint `9.7` TPE `jitml tune` render path.
- CpuFeatures CPUID detection, filesystem-backed `HasMinIO` checkpoint /
  inference / resume round-trips, the local Linux CPU checkpoint inference
  runner through a generated FFI kernel, decoded `.jmw1` weights passed into
  the weighted local inference runner, Dhall numerics decode coverage, and
  `KubectlSubprocess` command-shape coverage against the repo-local kubeconfig
  all run here.
- Real checkpoint round-trip against live HTTP MinIO and training transcript
  determinism are not present yet.

### Validation

1. `cabal test jitml-integration` exits `0` for the body.
2. Transferred live validation: the stanza spawns the real `jitml` binary
   through the typed `Subprocess` boundary, exercises a real checkpoint
   round-trip via MinIO, validates resume-from-checkpoint semantics, and
   round-trips a Dhall experiment through the typed decoder against the
   actual numerical-core catalog.

### Remaining Work

- No sprint-owned code-surface Remaining Work remains. Real checkpoint
  round-trip against `JitML.Service.MinIOSubprocess` and the live
  `HasMinIO` capability class is owned by
  [phase-15-linux-cuda-and-cluster-closure.md](README.md#legacy-to-new-phase-map)
  Sprint `15.7`. The per-substrate determinism assertion against real
  CUDA and Metal production kernels is owned by
  [phase-17-cross-substrate-and-handoff.md](README.md#legacy-to-new-phase-map)
  Sprint `17.1`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

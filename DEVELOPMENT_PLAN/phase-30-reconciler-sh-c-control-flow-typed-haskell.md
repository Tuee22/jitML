# Phase 30: Reconciler `sh -c` Control-Flow → Typed Haskell

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Reconciler sh -c Control-Flow → Typed Haskell. Single-session phase migrated from legacy Sprint 2.9 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 30.1: Reconciler `sh -c` Control-Flow → Typed Haskell [✅ Done]

**Status**: Done (re-closed 2026-07-15 after retained-cluster reconciliation
restored the missing typed Kind existence branch)
**Implementation**: `src/JitML/Cluster/Helm.hs`, `src/JitML/Bootstrap.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`, `documents/engineering/haskell_code_guide.md`, `legacy-tracking-for-deletion.md`

### Objective

Replace the embedded `sh -c` control-flow in the bootstrap reconciler with typed
multi-step Haskell and bounded typed retry/poll recursion. Implements doctrine
`Subprocesses as Typed Values`; the removed shell is tracked in the legacy
ledger. This sprint does not claim the daemon's Sprint `5.4` `RetryPolicy`
configuration reader.

### Deliverables

- `kindCreateSubprocess` / `kindDeleteSubprocess` / `helmDependencyBuildSubprocess`
  (`src/JitML/Cluster/Helm.hs`) and the postgres schema-grant step
  (`src/JitML/Bootstrap.hs`) express their existence checks, branching, and
  command-substitution as typed Haskell over leaf `subprocess` values instead of
  `sh -c` strings.
- The retry/poll loops are bounded typed-Haskell recursion over exact leaf
  subprocess outcomes, not shell `for`/`sleep`. Their explicit attempt/delay
  constants are reconciler-local; this sprint does not claim the daemon
  `RetryPolicy` reader.

### Validation

- `jitml bootstrap --<substrate> --dry-run` renders the equivalent typed plan.
- Focused Kind recovery/materialization integration covers clean creation,
  retained-cluster recovery, and fail-closed existence/probe failures.
- Phase `3` Sprint `3.7` exercises the retained branch through two exact live
  `linux-cpu` reconciles: the first converges and the second returns the
  documented exit code `3` without mutating retained state.

### Historical Validation State (2026-05-29)

- The 4 sh -c blocks (`kindCreate`, `kindDelete`, `helmDependencyBuild`,
  `postgresSchemaGrant`) are now typed: `JitML.Cluster.Helm` exposes typed
  `kind create cluster` / `kind delete cluster` / `helm dependency build`
  single-command subprocesses, and `JitML.Bootstrap` exposes
  `postgresSchemaGrantIO :: PerconaPGCluster -> IO (Either Text ())` —
  two typed `kubectl` subprocesses with the pod-name capture done in Haskell
  via `runStreaming`. `liveExecutePhasedRollout` splits the rollout into
  `livePreGrantSubprocessesForPort` + IO grants + `livePostGrantSubprocessesForPort`.
- `docker compose run --rm jitml cabal build all` (2026-05-29) succeeds.
- `cabal test jitml-unit` — all 185 tests pass.
- `cabal test jitml-integration` — only pre-existing live-cluster tests fail
  (Pulsar/MinIO/Harbor timeouts, no cluster up); the renderer assertions
  (`live phased rollout wires the explicit Kind image load phase`,
  `cluster down uses ... Kind delete subprocess`) pass against the typed forms.
- `jitml docs check` and `jitml bootstrap --linux-cpu --dry-run` exit `0`.
- The 2026-07-15 retained-Kind closure passes the expanded focused
  recovery/materialization suite **12 / 12**, strict warning-clean builds,
  Haskell lint, and the downstream Phase `3` two-run live acceptance.

### Remaining Work

- None. Phase `3` Sprint `3.7` completed the binding two-run retained-cluster
  and exit-`3` live validation on 2026-07-15.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

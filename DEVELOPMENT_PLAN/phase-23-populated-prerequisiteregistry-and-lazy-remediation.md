# Phase 23: Populated `prerequisiteRegistry` and Lazy Remediation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Populated prerequisiteRegistry and Lazy Remediation. Single-session phase migrated from legacy Sprint 2.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 23.1: Populated `prerequisiteRegistry` and Lazy Remediation [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Prerequisite/Nodes/Toolchain.hs`,
`src/JitML/Prerequisite/Nodes/Container.hs`,
`src/JitML/Prerequisite/Nodes/Cluster.hs`,
`src/JitML/Prerequisite/Plan.hs`, `src/JitML/App.hs`,
`src/JitML/CLI/Spec.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`,
`documents/engineering/cli_command_surface.md`

### Objective

Populate the typed `prerequisiteRegistry` (Sprint `1.7`) with the toolchain,
container, and cluster nodes consumed by `jitml bootstrap --<substrate>`. Shell
scripts only guard the stage-0 host gates; Haskell is the source of truth for
lazy package validation and remediation.

### Deliverables

- Toolchain nodes: `ghc-9.12.4`, `cabal-3.16.1.0`, `protoc`, `node`, `poetry`,
  `purescript`, `spago`, and Homebrew package nodes as typed values.
- Container nodes: `docker`, `colima` (Apple), `tart` (Apple, lazy first-JIT
  validation/install rather than bootstrap startup).
- Cluster nodes: `kind`, `kubectl`, `helm`, `kindest-node-pin` (verifies the
  pin in `./kind/cluster-<substrate>.yaml` matches the comment in
  `cabal.project`).
- Each node carries `nodeId`, `nodeDescription`, predicate, optional typed
  remediation `Subprocess`, `dependsOn`, postcondition validation, and a remedy
  hint.
- Homebrew remediation is Plan/Apply: pure plan construction decides what is
  missing; apply executes `brew install` or `brew upgrade` through the typed
  subprocess interpreter; postconditions validate before dependents run.
- `jitml doctor [--scope toolchain|container|cluster]` reports the chosen
  subgraph. `jitml doctor --scope <scope> --remediate` applies typed
  remediation actions and validates postconditions through the same typed
  subprocess boundary that `jitml bootstrap --<substrate>` uses lazily as
  resources are needed.

### Validation

1. `jitml doctor --scope toolchain` exits `0` on a fresh Apple Silicon host
   after `bootstrap/apple-silicon.sh doctor` completes.
2. The structured diagnostic on a synthetic missing `kindest/node` pin names
   the failing node, the description, and the remedy hint.

### Closure Checklist

- [x] Add toolchain, container, and cluster prerequisite node modules.
- [x] Replace the empty initial `prerequisiteRegistry` with the populated
  transitive DAG.
- [x] Wire `jitml doctor [--scope toolchain|container|cluster]` through
  `reconcilePrerequisites`.
- [x] Add synthetic missing-node diagnostics and scope-selection tests.
- [x] Complete positive `jitml doctor --scope toolchain` validation on a host
  with the Sprint `2.2` toolchain prerequisites installed.
- [x] Add typed Homebrew package prerequisite/remediation nodes and
  snapshot plan-render tests.
- [x] Ensure Apple JIT cache-miss prerequisites are absent from stage-0
  bootstrap and host-daemon startup; the old Tart node was later deleted by
  Sprint `2.10`.

### Closure Validation

- `jitml doctor --scope toolchain --remediate` installed the missing Homebrew
  package nodes through typed remediation actions and postcondition validation.
- `jitml doctor --scope toolchain` exits `0` on this Apple Silicon host after
  stage-0 `bootstrap/apple-silicon.sh doctor`.
- The Apple bootstrap/container prerequisite closure does not validate any
  cache-miss-only Apple build prerequisite during stage-0 bootstrap or
  host-daemon startup. The later Sprint `2.10` deletion removed the old
  `container.tart` node entirely.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

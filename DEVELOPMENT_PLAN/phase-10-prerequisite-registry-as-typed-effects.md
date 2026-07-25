# Phase 10: Prerequisite Registry as Typed Effects

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Prerequisite Registry as Typed Effects. Single-session phase migrated from legacy Sprint 1.7 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 10.1: Prerequisite Registry as Typed Effects [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Prerequisite/Registry.hs`,
`src/JitML/Prerequisite/Reconcile.hs`
**Docs to update**: `documents/engineering/haskell_code_guide.md`

### Objective

Stand up the typed `prerequisiteRegistry` per doctrine `Prerequisites as Typed
Effects`. This is the in-process source of truth that the bootstrap shell
scripts (Phase `2`) reflect.

### Deliverables

- `Prerequisite` record carrying `nodeId`, `nodeDescription`, predicate
  (`Env -> IO Bool`), optional remediation `Subprocess`, and `dependsOn :: [NodeId]`.
- `prerequisiteRegistry :: [Prerequisite]` is the in-process registry; the
  current tree is populated by later phases with toolchain, container, cluster,
  and frontend/infrastructure prerequisite nodes.
- `reconcilePrerequisites :: Env -> NodeId -> IO (Either AppError ())`
  evaluates the transitive closure rooted at `NodeId` and emits
  `AppError PrerequisiteUnmet (failingNodeId, description, remedyHint)` on
  failure. Exit code is `2`.
- `jitml doctor [--scope toolchain|container|cluster]` currently calls
  `reconcilePrerequisites`; `jitml doctor --scope <scope> --remediate` builds and
  applies typed remediation plans. The target live mutation leaves (`cluster up`,
  `train`, `tune`, `service`, `build`, `test all`) must call the prerequisite
  gate before effectful apply once those commands stop being local summaries.

### Validation

1. A synthetic missing prerequisite surfaces the typed error and exit `2`.
2. The structured diagnostic names the failing node, its description, and its
   remediation hint.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

# Phase 26: Superseded Apple Silicon VM Scaffold

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Superseded Apple Silicon VM Scaffold. Single-session phase migrated from legacy Sprint 2.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 26.1: Superseded Apple Silicon VM Scaffold [✅ Done]

**Status**: Done (historical; superseded again by Sprints `2.11` and `2.12`)
**Implementation**: Superseded by Sprint `2.10` at the time; Sprint `2.11`
later reintroduced Tart residue, and Sprint `2.12` now owns removing it for the
fixed-bridge Apple path.
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`

### Objective

This sprint originally delivered a local VM scaffold for the then-planned Apple
cache-miss build path. Sprint `7.8` later moved Apple Metal to a host
CommandLineTools `swift build` plus
runtime `MTLDevice.makeLibrary(source:)`, and Sprint `2.10` deleted the VM
prerequisite, CLI, and modules.

### Deliverables

- No current deliverable remains in this sprint. The fixed-bridge Apple path is
  owned by Sprint `2.12`: Apple cache entries are `.metal.json` source metadata,
  Tart/VM prerequisites are removed from the core path, and the generated-dylib
  symlink surface was deleted by Sprint `7.11`.
- The prior VM command group and prerequisite deletion is retained as dated
  history in
  [legacy-tracking-for-deletion.md → Completed](legacy-tracking-for-deletion.md#completed).

### Validation

- Sprint `2.10` validation was the 2026-05-30 closure gate for this superseded
  surface. Sprint `2.12` is the current validation gate for the fixed-bridge
  Apple prerequisite/cache model.

### Target Integration Notes

- First-cache-miss Apple execution now belongs to the fixed-bridge path in
  Sprint `7.11` and Phase `16` Sprint `16.9`.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

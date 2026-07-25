# Phase 79: Engine ABI and `Engines` Module Skeleton

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Engine ABI and Engines Module Skeleton. Single-session phase migrated from legacy Sprint 7.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 79.1: Engine ABI and `Engines` Module Skeleton [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Engines/Engine.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`

### Objective

Define the engine metadata shared by every substrate: backend
name, artifact extension, deterministic flags, typed kernel input/output
shapes, deterministic launch envelope, and renderable build plan.

### Deliverables

- `Engine` records `engineSubstrate`, `engineBackend`, and
  `engineArtifactExtension`.
- `engineForSubstrate` maps `apple-silicon` to `metal` / `.dylib`,
  `linux-cpu` to `onednn` / `.so`, and `linux-cuda` to `cuda` / `.so`.
- `deterministicFlags` records the current per-substrate determinism summary.
- `renderEnginePlan` renders the local engine metadata.
- `KernelInputs`, `KernelOutputs`, and `EngineEnvelope` record the local launch
  ABI and reproducibility witness surface.
- `renderEngineEnvelope` renders the envelope for deterministic inspection.
- Full production non-CPU `HasEngine` graph execution is validated by the
  Linux-CUDA and Apple-Silicon closure phases; the local Linux CPU oneDNN
  primitive execution path is implemented in `JitML.Engines.Local` and exposed through
  `JitML.Engines.HasEngine.LocalLinuxCpuEngine`.

### Validation

1. `cabal test jitml-cross-backend` verifies every substrate has
   deterministic flags.
2. `jitml-unit` validates local engine envelope rendering.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

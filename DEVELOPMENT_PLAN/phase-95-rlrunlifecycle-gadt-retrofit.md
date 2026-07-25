# Phase 95: `RLRunLifecycle` GADT Retrofit

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: RLRunLifecycle GADT Retrofit. Single-session phase migrated from legacy Sprint 8.7 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 95.1: `RLRunLifecycle` GADT Retrofit [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/RL/Framework.hs`, `test/unit/Main.hs`
**Docs to update**: `system-components.md`, `legacy-tracking-for-deletion.md`

### Objective

Retire the flat `RunPhase` enum and replace it with the phase-indexed
`RLRunLifecycle` GADT prescribed by doctrine `§ GADT-Indexed State Machines`,
so all three jitML lifecycles (`TrainingLifecycle`, `RLRunLifecycle`,
`TuneSweepLifecycle`) share the same singleton-witness shape.

### Deliverables

- `src/JitML/RL/Framework.hs` declares the `RLRunPhase` data kind
  (`RLCollect`, `RLComputeAdvantages`, `RLOptimise`, `RLEvaluate`,
  `RLCheckpoint`) and the singleton GADT `RLRunLifecycle phase` with
  constructors `SRLCollect`, `SRLComputeAdvantages`, `SRLOptimise`,
  `SRLEvaluate`, `SRLCheckpoint`.
- `rlRunPlan :: [RLRunPhase]` and `renderRLRunPhase :: RLRunPhase -> Text`
  preserve the existing five-step run ordering and rendered names.
- The module no longer exports `RunPhase` or `renderRunPhase`; consumers move
  to the GADT-backed surface.
- `test/unit/Main.hs` exercises `renderRLRunPhase` against `rlRunPlan` and
  pins the rendered phase ordering.
- The legacy-ledger row tracking the deviation moves from `Pending Removal`
  to `Completed`.

### Validation

1. `cabal build all` succeeds with the renamed `RLRunPhase` data kind and the
   `RLRunLifecycle` singleton GADT compiling under the existing GHC
   `9.12.4` / Cabal `3.16.1.0` toolchain.
2. `cabal test jitml-unit` passes; the
   `canonical RL environments and framework surfaces are deterministic` case
   continues to assert
   `["collect", "compute-advantages", "optimise", "evaluate", "checkpoint"]`.
3. `grep -RInE 'RunPhase|renderRunPhase' DEVELOPMENT_PLAN documents src test`
   reports no remaining references to the retired flat enum names outside the
   `Completed` ledger entry and this sprint description.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

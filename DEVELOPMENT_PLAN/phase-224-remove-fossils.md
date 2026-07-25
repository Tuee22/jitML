# Phase 224: Remove Fossils

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Remove Fossils. Single-session phase migrated from legacy Sprint 20.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 224.1: Remove Fossils [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/RL/VecEnv.hs`, `src/JitML/RL/Loop.hs`, `src/JitML/RL/SimulatorLoop.hs`, `src/JitML/RL/EpisodeEnvelope.hs`, `src/JitML/App.hs`, `jitml.cabal`, `test/rl-canonicals/Support/`
**Docs to update**: `../documents/engineering/jit_codegen_architecture.md`, `../documents/engineering/unit_testing_policy.md`, `legacy-tracking-for-deletion.md`

### Objective

Every fake-ML fossil is removed from product code or relocated into test-support
code, and the one product-facing type embedded in the fossil files — the episode
envelope consumed by the real trainers — is split out into its own product
module.

### Deliverables

- `src/JitML/RL/VecEnv.hs` is deleted; it is dead (zero callers under `src/`).
- The fake, non-learned policy runners — `runRLLoop` and `runOneEpisode`
  (`src/JitML/RL/Loop.hs`), `runSimulatedEpisode` /
  `runSimulatedEpisodes` / `runSimulatedEpisodesByName`
  (`src/JitML/RL/SimulatorLoop.hs`), and `deterministicStep`
  (`src/JitML/RL/Environments.hs`) — are relocated into a test-support module
  under `test/rl-canonicals/Support/`; they are off the product path because
  product RL dispatches through `App.hs:runTrainerEpisodes` into the real
  trainers.
- The `SimulatedEpisode` / `SimulatedFrame` **types** are split out of
  `SimulatorLoop.hs` into a product module `src/JitML/RL/EpisodeEnvelope.hs`,
  because they are the projection target the real trainers write into the
  Pulsar `EpisodeDone` publication path; the fake runners that populated them
  move to test-support and the product code imports only the envelope types.
- `src/JitML/App.hs:runTrainerEpisodes` (around line 3455) loses its stale
  docstring claim of a "deterministic per-episode simulator loop" fallback that
  no longer exists on the product path; the corrected docstring describes the
  real-trainer dispatch and the `EpisodeEnvelope` projection.
- `jitml.cabal` `exposed-modules`/`other-modules` drop `JitML.RL.VecEnv`, add
  `JitML.RL.EpisodeEnvelope`, and move the relocated runners into the
  `rl-canonicals` test target's module list.
- The determinism tests that legitimately exercise the relocated
  `deterministicStep` are retained under the test-support module with a
  `scaffolding:` title prefix so the scaffold lint and the reader both read them
  as test-only.
- `legacy-tracking-for-deletion.md` ledgers each removal — `VecEnv`,
  `runRLLoop`/`runOneEpisode`, `runSimulatedEpisode*`, `deterministicStep`
  relocation, and the `App.hs` docstring correction — naming Sprint `20.1` as the
  owning sprint and moving each from `Pending Removal` to `Completed` as it
  lands.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu          # passed, 246/246 tests
docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu # passed, 31/31 tests
docker compose run --rm jitml jitml docs check                           # passed
docker compose run --rm jitml jitml check-code                           # passed
```

### Closure Evidence

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

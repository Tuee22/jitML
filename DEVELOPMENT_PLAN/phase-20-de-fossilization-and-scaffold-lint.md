# Phase 20: De-Fossilization & Scaffold Lint

**Status**: Blocked
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md), [phase-19-product-truth-gates.md](phase-19-product-truth-gates.md), [phase-21-type-state-dsl-and-inference-eligibility.md](phase-21-type-state-dsl-and-inference-eligibility.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/jit_codegen_architecture.md](../documents/engineering/jit_codegen_architecture.md), [../documents/engineering/unit_testing_policy.md](../documents/engineering/unit_testing_policy.md), [../documents/engineering/code_quality.md](../documents/engineering/code_quality.md)
**Generated sections**: none

> **Purpose**: Delete the legacy fake-ML fossils from product code and install a
> forbidden-scaffold lint whose import-edge reachability check proves no product
> command path can reach a fake, deterministic, or seeded helper.

## Phase State

⏸️ **Blocked by** Phase `19`. Phase `19` installs the typed product matrix and
the forbidden-scaffold audit contract; this phase physically removes the fossils
that contract names and turns the reachability lint on. De-fossilization lands
**before** the scaffold lint so the lint does not red-flag live fossils that are
already scheduled for deletion here.

**Validation substrate**: `linux-cpu` only.

## Objective

Product code contains no fake-ML fossil. The dead vectorized-environment module
is gone, the deterministic fake-policy runners live only in test-support code,
and the product-facing episode envelope is a plain projection type consumed by
the real trainers. One lint pass — `src/JitML/Lint/ProductTruth.hs` — owns a
forbidden-scaffold registry scanned over `src/` and an import-edge reachability
check that fails when any module reachable from an `App.hs:runParsed` handler
imports a scaffold module. `jitml lint` and `jitml check-code` both run the pass,
and a registry `nonProductScaffolding` list plus its test guarantee no fossil can
be named as a `ProductRow` implementation.

## Sprint 20.1: Remove Fossils [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Phase `19`
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
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-rl --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Delete `VecEnv.hs` and relocate the fake runners plus `deterministicStep` into
  `test/rl-canonicals/Support/`.
- Create `src/JitML/RL/EpisodeEnvelope.hs`, repoint the real trainers and the
  `EpisodeDone` publication path at it, and update `jitml.cabal`.
- Fix the `runTrainerEpisodes` docstring and prefix the retained determinism
  tests with `scaffolding:`.
- Record every removal in the legacy ledger under Sprint `20.1`.

## Sprint 20.2: Scaffold Lint + Reachability [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `20.1`
**Implementation**: `src/JitML/Lint/ProductTruth.hs`, `src/JitML/Lint/Stack.hs`, `src/JitML/Product/Matrix.hs`, `test/unit/Main.hs`
**Docs to update**: `../documents/engineering/code_quality.md`, `../documents/engineering/unit_testing_policy.md`, `system-components.md`

### Objective

A single lint pass forbids product code from naming or importing any scaffold
helper, and an import-edge reachability check proves the product command graph
cannot reach a fossil module.

### Deliverables

- `src/JitML/Lint/ProductTruth.hs` owns a forbidden-scaffold registry —
  `deterministicStep`, `runRLLoop`, `runSimulatedEpisode`, `VecEnv`, the
  identity-copy family kernels, degenerate conv, `completedTrainingFromMetrics`,
  and seeded `*-demo-weights` hashes — scanned over `src/` only (`test/` is
  exempt so the relocated Sprint `20.1` scaffolding is legal).
- The pass adds an import-edge reachability check: starting from the
  `App.hs:runParsed` handlers, it walks the module import graph and fails when
  any product-reachable module imports a scaffold/fossil module.
- A `nonProductScaffolding` registry list plus a `test/unit/Main.hs` case
  guarantees no entry in that list is used as a `ProductRow.implementation` in
  `src/JitML/Product/Matrix.hs`.
- The pass is wired into `src/JitML/Lint/Stack.hs` alongside the existing
  `ForbiddenPaths`/`Chart`/`DhallNumerics` stages so it flows through both
  `jitml lint` and `jitml check-code`.
- The `code_quality.md` lint matrix and `system-components.md` lint inventory
  list the scaffold boundary and its reachability predicate.

### Validation

```bash
docker compose run --rm jitml jitml lint src
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Implement `ProductTruth.hs` with the registry and the reachability walk over
  the `runParsed` handler graph.
- Wire the stage into `Lint/Stack.hs` and add the `nonProductScaffolding` matrix
  guard test.
- Update `code_quality.md`, `unit_testing_policy.md`, and `system-components.md`
  to describe the new pass.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/jit_codegen_architecture.md` — record the scaffold
  boundary and that no product cache-miss path reaches a fossil helper.
- `documents/engineering/unit_testing_policy.md` — the `scaffolding:`-prefixed
  test-support home for the relocated deterministic runners and `deterministicStep`.
- `documents/engineering/code_quality.md` — the new `ProductTruth` lint pass, its
  forbidden-scaffold registry, and the import-edge reachability check.
- `system-components.md` — add `ProductTruth` to the lint-matrix inventory.

**Product docs to create/update:**
- None.

**Cross-references to add:**
- `legacy-tracking-for-deletion.md` records Sprint `20.1` as the owning sprint
  for each fossil removal and relocation.
- Add this phase to `README.md` and `00-overview.md`.
</content>
</invoke>

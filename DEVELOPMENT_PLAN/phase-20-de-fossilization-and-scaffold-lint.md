# Phase 20: De-Fossilization & Scaffold Lint

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md), [phase-19-product-truth-gates.md](phase-19-product-truth-gates.md), [phase-21-type-state-dsl-and-inference-eligibility.md](phase-21-type-state-dsl-and-inference-eligibility.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/jit_codegen_architecture.md](../documents/engineering/jit_codegen_architecture.md), [../documents/engineering/unit_testing_policy.md](../documents/engineering/unit_testing_policy.md), [../documents/engineering/code_quality.md](../documents/engineering/code_quality.md)
**Generated sections**: none

> **Purpose**: Delete the legacy fake-ML fossils from product code and install a
> forbidden-scaffold lint whose import-edge reachability check proves no product
> command path can reach a removed fake or deterministic helper.

## Phase State

✅ **Done** (reclosed 2026-07-06 after the 2026-07-05 realness audit). Phase `19`
installed the typed product matrix, the Phase `19`–`34` status registry, and the docs-check closure
guard. Sprint `20.1` removed the legacy fake-ML fossils from the product path, and
Sprint `20.2` turned on the forbidden-scaffold registry and reachability lint over
the de-fossilized tree.

**2026-07-05 audit finding, closed 2026-07-06.** The audit found that the Sprint
`20.2` scaffold lint still carried a `FutureOwner` exemption for
seeded-`*-demo-weights`. That exemption is deleted; all registry entries are
active, and the unit product-truth guard rejects a reintroduced
`mnist-demo-weights` scaffold. Validation: `jitml-unit` passed **277 / 277** and
`jitml-negative-controls` passed **3 / 3** on `linux-cpu`.

**Validation substrate**: `linux-cpu` only.

## Objective

Product code contains no Sprint `20.1` fake-ML fossil. The dead
vectorized-environment module is gone, the deterministic fake-policy runners
live only in test-support code, and the product-facing episode envelope is a
plain projection type consumed by the real trainers. One lint pass —
`src/JitML/Lint/ProductTruth.hs` — owns a forbidden-scaffold registry scanned
over `src/` for entries that are enforced now and an import-edge reachability
check that fails when `JitML.App` reaches a scaffold module. The same registry
tracks future-owned scaffold entries for later phases without enforcing their
source removal before their owning sprint. `jitml lint files` and
`jitml check-code` both run the pass, and a `nonProductScaffolding` list plus
its test guarantee no fossil can be named as a `ProductRow` implementation.

## Sprint 20.1: Remove Fossils [✅ Done]

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

## Sprint 20.2: Scaffold Lint + Reachability [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Lint/ProductTruth.hs`, `src/JitML/Lint/Stack.hs`, `src/JitML/Product/Matrix.hs`, `test/unit/Main.hs`
**Docs to update**: `../documents/engineering/code_quality.md`, `../documents/engineering/unit_testing_policy.md`, `system-components.md`

### Objective

A single lint pass forbids product code from naming or importing any scaffold
helper, and an import-edge reachability check proves the product command graph
cannot reach a fossil module.

### Deliverables

- `src/JitML/Lint/ProductTruth.hs` owns a forbidden-scaffold registry. Entries
  enforced by Sprint `20.2` — `deterministicStep`, `runRLLoop`,
  `runSimulatedEpisode*`, and `VecEnv` / `JitML.RL.VecEnv` — are scanned over
  `src/` only (`test/` is exempt so the relocated Sprint `20.1` scaffolding is
  legal).
- The same registry also carries future-owner entries for seeded
  `*-demo-weights`, identity-copy CUDA kernels, and degenerate CUDA/Metal
  convolution scaffolds. Those names feed the `ProductRow` implementation guard
  now, while hard source removal remains owned by Sprints `27.1`, `29.1`, and
  `30.1` in numerical order. Sprint `21.1` later promotes
  `completedTrainingFromMetrics` from future-owned entry to enforced removal.
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

The forbidden-module list is scoped to *dead* fakes: `JitML.RL.VecEnv` is
forbidden by name here only because the original module was a dead, zero-caller
fossil. When Phase `25` reintroduces a real, product-reachable, learning
`JitML.RL.VecEnv` (vectorized environments), the lint's forbidden-module entry
for that name is refined to permit the real module while the reachability walk
still fails any dead fossil. That refinement is owned by Phase `25`'s Remaining
Work and does not reopen Phase `20`.

### Validation

```bash
docker compose run --rm jitml jitml lint files                 # passed
docker compose run --rm jitml jitml test jitml-unit --linux-cpu # passed, 249/249 tests
docker compose run --rm jitml jitml docs check                  # passed
docker compose run --rm jitml jitml check-code                  # passed
```

### Closure Evidence

- **Closed obligation (Exit Definition: no product command path executes a fake).**
  As landed, `src/JitML/Lint/ProductTruth.hs` is a *name denylist* of the previous
  iteration's fossil names (`deterministicStep`, `runRLLoop`,
  `runSimulatedEpisode*`, `VecEnv` / `JitML.RL.VecEnv`) with a `FutureOwner`
  exemption that registers the seeded-`*-demo-weights` entries but never scans
  their behaviour. A new fake introduced under a new name — or hidden behind an
  exempted `FutureOwner` name — passes the lint unseen, so the pass does not prove
  the product command graph is free of fakes; it only re-checks yesterday's fossils.
- **Closing change.** Replace the name denylist with a *behavioral* detector that
  answers "does this product function's output depend on the trained weights?" over
  the product-reachable import graph, and delete the `FutureOwner` exemption so no
  name is waved through unscanned.
- **Negative-control validation.** This obligation is owned and closed by the Phase
  `32` anti-fake harness:
  [phase-32-external-truth-realness-harness.md](phase-32-external-truth-realness-harness.md)
  Sprint `32.3` reimplements `ProductTruth.hs` as the behavioral detector and
  deletes the `FutureOwner` exemption, and the `jitml-negative-controls` suite
  (Sprint `32.1`) proves it by requiring the lint to *reject* a committed new-name
  fake (e.g. a dense layer labelled as convolution, or a stand-in whose output
  ignores the checkpoint):
  `docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu`.

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

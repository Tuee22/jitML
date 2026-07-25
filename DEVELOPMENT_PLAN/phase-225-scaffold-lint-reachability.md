# Phase 225: Scaffold Lint + Reachability

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Scaffold Lint + Reachability. Single-session phase migrated from legacy Sprint 20.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 225.1: Scaffold Lint + Reachability [✅ Done]

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
  [phase-32-external-truth-realness-harness.md](README.md#legacy-to-new-phase-map)
  Sprint `32.3` reimplements `ProductTruth.hs` as the behavioral detector and
  deletes the `FutureOwner` exemption, and the `jitml-negative-controls` suite
  (Sprint `32.1`) proves it by requiring the lint to *reject* a committed new-name
  fake (e.g. a dense layer labelled as convolution, or a stand-in whose output
  ignores the checkpoint):
  `docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

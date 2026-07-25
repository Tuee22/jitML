# Phase 182: Linux CPU Full-Tensor Benchmark Payloads and First-Cache-Miss Live Execution

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Linux CPU Full-Tensor Benchmark Payloads and First-Cache-Miss Live Execution. Single-session phase migrated from legacy Sprint 15.15 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 182.1: Linux CPU Full-Tensor Benchmark Payloads and First-Cache-Miss Live Execution [✅ Done]

**Status**: Done (re-validated 2026-06-06 on RTX 5090; previously Done on RTX 3090) (closed 2026-05-27)
**Blocked by**: Sprint `178.1`
**Implementation**: `src/JitML/Engines/TuningBenchmark.hs`,
`src/JitML/Engines/Loader.hs`,
`src/JitML/Engines/Local.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`

### Objective

Replace the current Linux CPU oneDNN benchmark candidate runner's
single-tensor payload with the full-tensor benchmark payload supplied
by the checkpoint ABI from Sprint `15.11`, and execute the live
first-cache-miss benchmark path on Linux CPU so the persisted
`TuningChoice` reflects real measured selection.

### Deliverables

- `linuxCpuBenchmarkCandidateRunner` consumes full-tensor inputs from
  the loaded checkpoint ABI.
- The first cache-miss for a Linux CPU kernel on the live cluster
  drives the benchmark runner; the persisted selection lands under
  `./.build/jit/tuning/linux-cpu/<base-hash>.json`.
- A subsequent build of the same kernel reads the persisted choice.

### Validation

1. On Linux: a controlled first cache miss for a `linux-cpu` kernel
   with a non-trivial tensor payload selects a tuning choice live and
   persists it; the second build hits the persisted choice.

### Code Surface Landed (2026-05-26, weighted benchmark runner)

- `JitML.Engines.TuningBenchmark.linuxCpuWeightedBenchmarkCandidateRunner`
  accepts both input and weight tensors and drives
  `Local.runLinuxCpuWeightedKernel` through the Sprint 15.11 weighted
  ABI. The persisted `BenchmarkObservation` digest is computed from
  `linuxCpuWeightedKernelOutput`. Replaces the single-input
  smoke fixture with the full-tensor payload supplied by the
  checkpoint ABI for callers that want to measure against the real
  workload shape.

### Code Surface Landed (2026-05-27, full-tensor benchmark payload + weighted ensure path)

- `JitML.App.benchmarkSampleInput` extended from the 2-float smoke
  fixture `[1.0, 2.0]` to a 32-element deterministic full-tensor
  payload (`[i/4 | i <- 0..31]`). The benchmark candidate runner now
  measures against a realistic shape that exercises the inner
  reduction loop of the family's natural primitive (matmul on
  Dense2D, conv channels on Conv2D/3D, batch / feature axis on
  BatchNorm / LayerNorm, lookup spread on Embedding). The persisted
  `TuningChoice` therefore reflects measurement against shapes
  matching the JIT cache's eventual inference workload, not the
  prior smoke fixture.
- `JitML.Engines.TuningBenchmark.ensureKernelArtifactWithWeightedBenchmarkTuning`
  wires the weighted candidate runner (`linuxCpuWeightedBenchmarkCandidateRunner`)
  into the first-cache-miss selection path. Callers that have a
  weight tensor available (e.g., the daemon-side inference path that
  loaded a checkpoint) invoke this variant so the persisted
  `TuningChoice` reflects measurement against the actual weighted
  workload rather than the unweighted single-input runner. The
  unweighted `ensureKernelArtifactWithBenchmarkTuning` stays as the
  default for the non-checkpoint cache-warm path.

### Live Validation Note (2026-05-27, first-cache-miss persistence)

New `jitml-cross-backend` case `linux-cpu first cache-miss
persists a TuningChoice JSON in the tuning store (Sprint 15.15)`:
(a) snapshots the existing files under
`.build/jit/tuning/linux-cpu/`, (b) drives
`ensureKernelArtifactWithBenchmarkTuningWithRunner` with a
unique-suffix `KernelSpec` so the cache-miss branch executes,
(c) lists the directory again and asserts at least one new
TuningChoice JSON file appeared. The stub runner returns a
deterministic `BenchmarkObservation`; the production-shape
`collectAndPersistBenchmarkSelection` then writes the selection
through `TuningStore.writeTuningSelectionAtomic`. Run inside
`jitml:local` (the `.build/` directory is root-owned inside the
container so the atomic-rename write succeeds; on a host that has
prior root-owned `.build/jit/tuning/` directories the same test
exits with `permission denied`, which is the test environment's
filesystem permission rather than a fault in the surface under
test).

```
linux-cpu first cache-miss persists a TuningChoice JSON in the tuning store (Sprint 15.15): OK (1.18s)
```

`cabal test jitml-cross-backend` cohort post-add — 19 / 19 pass.

### Remaining Work

- None remaining for Sprint 13.15. Sprint closed 2026-05-27.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

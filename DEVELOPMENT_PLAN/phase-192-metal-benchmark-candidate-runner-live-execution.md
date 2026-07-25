# Phase 192: Metal Benchmark Candidate Runner Live Execution

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Metal Benchmark Candidate Runner Live Execution. Single-session phase migrated from legacy Sprint 16.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 192.1: Metal Benchmark Candidate Runner Live Execution [✅ Done]

**Status**: Done (validated headless 2026-05-31, Apple M1 / macOS 26)
**Blocked by**: Sprint `191.1` (closed)
**Implementation**: `src/JitML/Engines/TuningBenchmark.hs`,
`src/JitML/Engines/MetalLocal.hs`,
`src/JitML/Engines/Loader.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`

### Objective

Replace the guarded preflight `metalBenchmarkCandidateRunner` with the
real Metal candidate runner: render the tuned Swift/Metal source,
compile through Sprint `16.1`'s host `swift build`, load + runtime-compile
through Sprint `16.2`'s FFI runner, measure latency, and capture an output digest.
The benchmark driver in `ensureKernelArtifact`'s first-cache-miss path
selects the Metal tuning choice for an `apple-silicon` kernel and
persists it via `Engines.TuningStore`.

### Deliverables

- `metalBenchmarkCandidateRunner` becomes a non-stub: it renders the
  candidate Metal source, drives the Sprint `16.1` host build, loads +
  runtime-compiles through Sprint `16.2`'s runner, measures elapsed time, and
  records the SHA-256 of the float output.
- The benchmark driver wired into `ensureKernelArtifact` in Sprint
  `7.6`'s code-only Remaining Work invokes the Metal runner on the
  first Apple cache miss; the persisted selection appears under
  `./.build/jit/tuning/apple-silicon/<base-hash>.json`.

### Validation

1. On Apple Silicon: a controlled first cache miss for an
   `apple-silicon` kernel selects a tuning choice through the live
   Metal runner, persists the selected `TuningChoice`, and the next
   build of the same kernel reads the persisted choice (cache hit on
   the tuned key).

### Code Surface Landed (2026-05-30)

- `JitML.Engines.TuningBenchmark.metalBenchmarkCandidateRunner` is
  de-stubbed: it now takes `Env`, renders the tuned Metal package for the
  candidate, drives the host build + FFI launch through
  `MetalLocal.runMetalKernel`, times the round-trip with
  `getMonotonicTimeNSec`, and records the SHA-256 of the float output —
  the mirror of `cudaBenchmarkCandidateRunner`. `candidateRunnerForSubstrate
  AppleSilicon` routes to it directly.
- The `jitml-unit` "CUDA and Metal runners preflight runtime availability"
  case is updated for the new arity and passes; the live FFI measurement is
  exercised through `jitml-cross-backend` headless on a Metal-capable Apple
  host. Compiles host-native.

### Validation (passed 2026-05-31, Apple M1 / macOS 26, headless)

1. `jitml-cross-backend` "apple-silicon live Metal benchmark candidate runner
   produces a measurement" runs `metalBenchmarkCandidateRunner` on a real
   candidate (one host `swift build` + runtime `makeLibrary` + Metal launch),
   asserting a non-negative latency and the expected SHA-256 output digest,
   plus the wrong-substrate rejection.
2. The gated "apple-silicon first cache-miss persists and reuses a TuningChoice
   via the live runner" case (run with `JITML_TUNING_LIVE=1`) drove the full
   24-candidate Apple knob-space sweep (24 live host builds, 667 s), persisted
   a measured `TuningChoice` JSON under
   `./.build/jit/tuning/apple-silicon/<base-hash>.json`
   (`choice=threadgroup-size=64;matmul-tile=32x32;…`), and the second
   `ensureKernelArtifactWithBenchmarkTuning` call reused the persisted choice
   (no re-sweep). The expensive sweep stays gated so the routine suite is fast.

### Remaining Work

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

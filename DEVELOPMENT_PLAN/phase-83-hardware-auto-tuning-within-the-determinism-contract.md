# Phase 83: Hardware Auto-Tuning Within the Determinism Contract

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Hardware Auto-Tuning Within the Determinism Contract. Single-session phase migrated from legacy Sprint 7.6 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 83.1: Hardware Auto-Tuning Within the Determinism Contract [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface only. The Metal
candidate runner live execution migrated to Phase `16` Sprint `16.3`.
The Linux CPU full-tensor benchmark payload migration and live
first-cache-miss measurement migrated to Phase `15` Sprint `15.15`.
The cross-substrate equality test migrated to Phase `17` Sprint `17.1`.
The code-only benchmark-runner wiring into `ensureKernelArtifact`'s
first-cache-miss path closed on 2026-05-24 through
`JitML.Engines.TuningBenchmark.{ensureKernelArtifactWithBenchmarkTuning,
ensureTuningSelection,candidateRunnerForSubstrate}`; the live runtime
validation remains owned by Phase `15` Sprint `15.15`.
**Implementation**: `src/JitML/Cache/Key.hs`,
`src/JitML/Engines/Tuning.hs`, `src/JitML/Engines/TuningBenchmark.hs`,
`src/JitML/Engines/TuningStore.hs`,
`src/JitML/Engines/TuningCache.hs`, `src/JitML/App.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`

### Objective

Expose `TuningChoice` as a cache-key input and deterministic metadata
string, plus the deterministic measurement-ranking boundary for benchmark
results and the persisted selected-choice record; grow real hardware
benchmarking and per-substrate auto-tuning per `### Remaining Work` below.

### Deliverables

- `TuningChoice` is a typed cache-key input in `src/JitML/Cache/Key.hs`.
- `defaultTuningChoice` is the default choice.
- Runtime source renderers embed the tuning choice into generated source
  payloads.
- `cacheKey` includes the tuning choice and rendered-source payload, so changes
  invalidate the local cache key.
- `src/JitML/Engines/Tuning.hs` defines per-substrate `KnobSpace`
  values: `appleSiliconKnobs` (threadgroup-size, matmul-tile,
  reduction-strategy, command-queue-discipline), `linuxCpuKnobs`
  (micro-kernel, reduction-block, thread-count, fastmath off),
  `linuxCudaKnobs` (matmul-tile, block-dim, cuDNN deterministic algo,
  reduction-strategy, no-TF32, no-fast-math). `selectDeterministic`
  picks the deterministic default per axis; `tuningChoiceForResult`
  emits the cache-key payload string.
- `benchmarkPlan` enumerates the deterministic-only candidate
  `TuningResult`s for a `KnobSpace`, and `renderBenchmarkPlan` renders their
  cache-key `TuningChoice` payloads in stable order.
- `BenchmarkMeasurement` records a candidate `TuningResult`, measured
  latency in microseconds, and output digest; `selectMeasuredTuning`
  rejects measurements outside the plan or with negative latency, then
  selects the lowest-latency candidate with stable plan-order tie-breaking.
- `JitML.Engines.TuningStore` persists the selected measured result as JSON
  under `jit/tuning/<substrate>/<base-hash>.json`, records the selected
  `TuningChoice`, latency, and output digest, and validates that reads match
  the requested substrate and base hash.
- `JitML.Engines.TuningBenchmark` collects candidate measurements in stable
  benchmark-plan order through a typed candidate runner, records latency and
  SHA-256 output digests for float/double outputs, and can persist the selected
  measurement by base hash through `TuningStore`.
- `JitML.Engines.TuningCache` derives the default tuning base hash, reads a
  persisted selected `TuningChoice` for that base hash when present, renders the
  tuned runtime source, and computes the final cache key from the selected
  choice. `jitml build --dry-run` prints the base hash, selected tuning choice,
  and whether the choice came from the default or persisted path.
- `JitML.Engines.TuningBenchmark.linuxCpuBenchmarkCandidateRunner` supplies the
  first concrete candidate runner: for `linux-cpu` candidates it renders the
  tuned oneDNN-style source, computes the candidate cache key, compiles/loads
  through `JitML.Engines.Local.runLinuxCpuKernel`, measures elapsed time, and
  records the SHA-256 digest of the FFI output.
- `JitML.Engines.TuningBenchmark.cudaBenchmarkCandidateRunner` provides the
  live CUDA candidate runner: it rejects wrong-substrate candidates, refuses
  to compile when `probeCudaRuntime` reports the runtime is unavailable
  (returning the typed unavailable summary), and otherwise renders the tuned
  CUDA runtime source, computes the candidate cache key, compiles/loads
  through `JitML.Engines.CudaLocal.runCudaKernel`, measures elapsed time, and
  records the SHA-256 digest of the FFI output. The signature matches
  `linuxCpuBenchmarkCandidateRunner`, including the `Env` parameter that
  carries the JIT cache root.
- In the historical Sprint `7.6` snapshot,
  `JitML.Engines.TuningBenchmark.metalBenchmarkCandidateRunner` was still a
  guarded preflight. Later Sprint `16.3`/`16.9` validation superseded that
  snapshot: live Metal candidate measurement now runs through the fixed bridge
  on Apple Silicon.

### Validation

1. `jitml-unit` verifies the rendered runtime-source payload participates
   in the cache key, the CUDA benchmark plan enumerates 72 deterministic
   candidates and includes the deterministic default `TuningChoice`, and
   measured selection chooses the fastest deterministic candidate with stable
   tie-breaking and empty-plan rejection.
2. `jitml-unit` verifies selected measured choices persist by base hash and
   round-trip through `JitML.Engines.TuningStore`, then
   `JitML.Engines.TuningCache` loads the persisted choice and derives a
   distinct final cache key from it.
3. `jitml-unit` verifies `JitML.Engines.TuningBenchmark` collects measurements
   in plan order, captures content-sensitive float output digests, measures
   non-negative elapsed time, and persists the lowest-latency selected
   measurement.
4. `cabal test jitml-cross-backend` revalidated on 2026-05-21 that the
   Linux CPU generated identity kernel produces bit-identical output
   across repeated FFI executions.
5. `docker compose run --rm jitml cabal test jitml-cross-backend` on
   2026-05-22 validates the Linux CPU benchmark candidate runner against the
   generated-kernel FFI path and verifies candidate-output digest capture.
6. `docker compose run --rm jitml cabal test jitml-unit --test-options='-p CUDA'`
   and `docker compose run --rm jitml cabal test jitml-unit --test-options='-p Metal'`
   on 2026-05-23 validate the guarded CUDA/Metal benchmark runner preflight
   boundaries, including wrong-substrate rejection and unavailable-runtime
   summaries. The CUDA preflight case for "available runtime" now routes
   into the live CUDA FFI candidate runner; the explicit
   not-implemented-yet assertion remains only on the Metal preflight path.
7. `docker compose run --rm jitml jitml build --dry-run --substrate linux-cpu`,
   `linux-cuda`, and `apple-silicon` revalidated on 2026-05-21 that the current
   runtime-source renderers still emit the expected oneDNN, CUDA, and
   Metal/Swift compile plans, including the selected tuning metadata
   (`tuning_base_hash`, `tuning_choice`, `tuning_selection`).
8. `docker compose build jitml`,
   `docker compose run --rm jitml jitml docs check`, and
   `docker compose run --rm jitml jitml check-code` passed on 2026-05-21,
   confirming the container-owned documentation and code-quality path.
9. Transferred live validation: per-substrate knob spaces drive
   benchmark-based selection on real hardware (matmul tile sizes,
   reduction strategies, cuDNN deterministic algorithm IDs) and the
   chosen tuning influences the cache key without breaking determinism.

### Remaining Work

- No sprint-owned code-surface Remaining Work remains. The
  `ensureKernelArtifactWithBenchmarkTuning` /
  `ensureKernelArtifactWithBenchmarkTuningWithRunner` /
  `ensureTuningSelection` wiring in
  `JitML.Engines.TuningBenchmark` selects the substrate-specific candidate
  runner (`linuxCpuBenchmarkCandidateRunner`,
  `cudaBenchmarkCandidateRunner`, `metalBenchmarkCandidateRunner`),
  drives the deterministic benchmark plan, persists the lowest-latency
  selection through `TuningStore`, and re-resolves the tuned
  `TuningCachePlan` before invoking `ensureKernelArtifact`. `jitml build`
  routes Linux CPU and Linux CUDA non-dry-run builds through the tuned ensure
  path; Phase `16` Sprint `16.3` closed the Apple Metal candidate-runner live
  path on top of the same headless Swift/Metal build surface. The 2026-05-24 in-container
  `cabal test jitml-unit -p "ensureTuningSelection"` validates the
  synthetic runner is invoked exactly once per candidate on first call
  and is not invoked again on the cached re-resolution. The live runtime
  validation that hardware-tuned choices get selected during real
  compilation is owned by Phase `15` Sprint `15.15` (Linux CPU) and Phase
  `16` Sprint `16.3` (Metal). The cross-substrate equality test (linux-cpu
  vs apple-silicon vs linux-cuda) and the full-tensor benchmark payload
  migration moved to Phase `17` Sprint `17.1` and Phase `15` Sprint
  `15.15` respectively.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

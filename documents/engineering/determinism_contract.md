# Determinism Contract

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/00-overview.md, ../../DEVELOPMENT_PLAN/system-components.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-7-jit-codegen-and-substrates.md, ../../DEVELOPMENT_PLAN/phase-9-rl-catalog-alphazero-and-tuning.md, ../../DEVELOPMENT_PLAN/phase-10-checkpointing-and-inference.md, ../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md, checkpoint_format.md, jit_codegen_architecture.md, training_workloads.md, unit_testing_policy.md
**Generated sections**: none

> **Purpose**: Project-specific bit-determinism contract for jitML — the per-
> substrate floating-point semantics, the RNG split and per-experiment seed
> derivation, the JIT cache content-addressing, the engine envelope shape, and
> the cross-substrate tolerance methodology.

## The Contract

jitML guarantees **same-substrate bit-equality**: a transcript or checkpoint
produced on `<substrate>` is bit-identical when reproduced on the same
`<substrate>` against the same toolchain pin (every codegen-toolchain
fingerprint from `cabal.project` plus the substrate-specific kernel-compiler
version). Cross-substrate bit-equality is **not** guaranteed; cross-substrate
drift is bounded by a per-tensor tolerance band.

Reproducibility is an architectural invariant, not a debugging aid. The
contract holds across:

- parameter initialization (seeded by the experiment Dhall),
- minibatch ordering (dataset shuffle is seeded),
- optimizer state (numerical updates are deterministic),
- RL trajectories (env reset and step are seeded),
- MCTS exploration paths (per-node-expansion seed is derived
  deterministically),
- hyperparameter-trial selection (sampler state is reproducible),
- checkpoint recovery (the `.jmw1` decode + manifest reload restore identical
  state).

## Per-Substrate Floating-Point Semantics

Per [../README.md → Substrates and runtime
modes](../../README.md#substrates-and-runtime-modes), each substrate carries its
own floating-point determinism contract.

### `apple-silicon` (Metal)

- Metal compute kernels execute on the host GPU.
- Float-accumulation order is fixed by the kernel's reduction tree (no
  `-ffast-math`).
- Generated reduction metadata reports one output per simdgroup partial
  (`ceil(n / 32)`), so future Metal FFI loading can size host buffers from the
  generated `jitml_kernel_output_count` symbol instead of duplicating shape
  logic outside the renderer.
- Metal compute kernels are built inside the `jitml-build` Tart VM (which ships
  Xcode 16 pre-installed and pre-licensed) and execute on the host GPU through
  the host's Metal framework. `JitML.Engines.MetalRuntime` probes host Metal
  device visibility and the loadable VM-built `.dylib` through typed
  subprocesses; the host has no Swift/Xcode build toolchain and never compiles
  shaders — all `swift build` / `metal` shader compilation happens in the VM via
  `tart exec`. Full Xcode is never installed on the host (its first-launch/license
  UI breaks the headless workflow), so a host `xcrun -find metal` failure is by
  design and is never remediated by installing host Xcode.
- RNG state lives in the host daemon (`Host + SelfInference`).
- Kernel-launch ordering is single-stream by default. Single MTLCommandQueue
  with FIFO ordering; explicit barriers prevent kernel reordering.
- **Tradeoff**: single-stream launch forfeits the multi-stream concurrency
  that hides launch latency at small batch sizes — the throughput cost is
  real and is the price of the bit-determinism contract.

### `linux-cpu` (oneDNN)

- oneDNN dispatches to a per-host vector ISA detected at JIT time through
  typed subprocess probes (AVX2 baseline, AVX-512 detected and used when
  available).
- The production Linux CPU path uses generated C++ that includes oneDNN
  headers, links `-ldnnl`, and launches oneDNN primitives through the stable
  `jitml_kernel` FFI ABI.
- The oneDNN runtime/link availability probe checks `pkg-config` package
  metadata, readable oneDNN headers, and dynamic-linker `libdnnl` visibility.
- Reductions are blocked with a fixed block size so the accumulation tree is
  host-independent. The block size is part of `ToolchainFingerprint`; a
  block-size change invalidates the cache key.
- RNG state lives in the clustered service pod.

### `linux-cuda` (CUDA C + cuBLAS / cuDNN)

- CUDA kernels disable `--use_fast_math`.
- Per-block reductions use a deterministic warp-shuffle pattern. Generated CUDA
  reduction source emits one partial per warp and avoids device-side atomics;
  `JitML.Engines.CudaRuntime` validates the expected partial count and
  accumulates partials on the host in canonical index order.
- Generated CUDA artifacts expose a host-callable
  `jitml_kernel(float*, const float*, size_t)` FFI wrapper. The wrapper owns
  device-buffer allocation, input copy, deterministic device-kernel launch,
  synchronization, and output copyback before the Haskell side observes the
  result.
- cuBLAS and cuDNN are pinned to deterministic algorithm selections via
  `cudnnSetConvolutionMathType` plus explicit algorithm-id pinning. The
  cuDNN algorithm-id selection is restricted to the deterministic-only set.
- RNG is the host's SplitMix64 stream from `JitML.Engines.Rng`, never the GPU's
  curand. Generated CUDA source records the `host-splitmix64-no-curand` policy
  in the rendered source payload.
- **Tradeoff**: cuDNN's deterministic convolution algorithms are typically
  20–50% slower than the non-deterministic defaults on training workloads;
  this is the price of the bit-determinism contract.

## RNG Split and Per-Experiment Seed Derivation

The master seed is declared in the experiment Dhall. Per-experiment seeds are
derived deterministically by `JitML.Engines.Rng.deriveSplitMixSeed`:

```
experimentSeed = splitmix64(masterSeed, experimentIndex)
```

For multi-game / multi-environment workloads (RL self-play, AlphaZero), the
per-game seed derivation is:

```
perGameSeed = splitmix64(experimentSeed, gameIndex)
```

This makes per-game output independent of worker count, scheduling order, and
worker-to-game assignment. The same property holds for hyperparameter trial
seeds and for the MCTS root-noise seed in AlphaZero.

## JIT Cache Content-Addressing

The JIT cache key is the six-tuple

```
sha256(canonical-cbor(KernelSpec) || kind || substrate || toolchain-fingerprint || rendered-source-payload || tuning-choice)
```

where:

- `KernelSpec` is the typed model shape (layer topology, dtype layouts,
  activation choices, optimizer + loss when `kind = Training`).
- `kind` ∈ `Training | Inference`. Training and inference kernels are
  separate artefacts — training carries the backward pass plus optimizer-
  step kernel; inference is forward-only with frozen-weight constant folding
  enabled.
- `substrate` ∈ `apple-silicon | linux-cpu | linux-cuda`.
- `toolchain-fingerprint` is the hash of every codegen-toolchain pin from
  `cabal.project` (LLVM, NVCC, Xcode/Metal, oneDNN) plus loader-relevant ABI
  facts for local FFI artifacts. The Apple `Xcode/Metal` pin is the Xcode 16
  that ships pre-installed and pre-licensed inside the `jitml-build` Tart VM —
  never a host Xcode, which is never installed. The current Linux CPU local fingerprint carries
  `artifact-abi=<os>-<arch>` so Darwin host artifacts and Linux container
  artifacts do not share a cache key.
- `rendered-source-payload` is the canonical Haskell-rendered source bundle
  produced by `renderRuntimeSource`.
- `tuning-choice` is the selected auto-tuning choice.

A change in any input invalidates the cache key, so a re-JIT is
substrate-explicit and toolchain-explicit.

## Engine Envelope

The current local `EngineEnvelope` in `src/JitML/Engines/Engine.hs` captures
the kernel handle, input/output shape metadata, deterministic flag list, and
compile command for deterministic inspection. `JitML.Engines.Loader` records
whether that compile command was actually executed for the current cache lookup
or whether an existing content-addressed artifact was reused. Target checkpoint
manifests carry a richer typed `EngineEnvelope` block with substrate-specific
reproducibility witnesses:

| Substrate | Envelope fields |
|-----------|-----------------|
| `apple-silicon` | GPU device id, Metal version, Xcode version |
| `linux-cpu` | Detected ISA (AVX2 / AVX-512), oneDNN version, glibc version, CPU model |
| `linux-cuda` | cuDNN version, cuBLAS version, CUDA driver version, GPU compute capability, NVCC version |

The envelope is **not** part of the cache key — two cohort-equal envelopes
should produce bit-identical kernel output by the contract. The envelope is
the forensic record that lets `jitml inspect replay` detect substrate drift
rather than silently displaying ULP-shifted floats as if they were the
originator's.

## Same-Substrate Bit-Equality (RL Caveat)

For off-policy RL algorithms (DQN, DDPG, TD3, SAC, CrossQ, TQC), full-run
determinism is sensitive to scheduler order: the replay-buffer write
discipline is `Async`, so two same-substrate same-seed runs may differ in
which step pulls a particular sample. The bit-equality anchor for
off-policy algorithms is therefore the **first-N-steps prefix** (default
`rl_steps / 10` per
[../../DEVELOPMENT_PLAN/system-components.md → POC Report-Card
Knobs](../../DEVELOPMENT_PLAN/system-components.md#poc-report-card-knobs)),
asserted by comparing two fresh runs against each other — never against
a stored trajectory file.

For on-policy algorithms (PPO, A2C, TRPO, MaskablePPO, RecurrentPPO),
full-run bit-equality holds.

For SL training, full-run bit-equality holds.

For AlphaZero self-play, per-game bit-equality holds (deterministic
stochasticity).

The current local Phase 7 executable anchor proves the Linux CPU side of the
runtime contract: `jitml-cross-backend` runs the Linux CPU oneDNN reorder,
reduction, matmul, convolution, normalization, attention, and embedding kernels
through `JitML.Engines.Local`, verifies the loaded artifact reports the expected
`jitml_kernel_family_name` and `jitml_kernel_output_count`, and asserts
repeated identity-kernel output is bit-identical. It also exercises the local
Linux CPU `HasEngine` interpreter over the generated-family FFI path and
measures the Linux CPU benchmark candidate runner against generated FFI output
while recording a deterministic output digest. The generated CUDA source bundle
now exports the same `jitml_kernel` / family / output-count ABI and the guarded
`JitML.Engines.CudaLocal` runner consumes a positive CUDA runtime probe before
compile/load/launch; in unavailable environments it fails closed before compile.
Swift/Metal source bundles export the same family/output-count metadata
contract for their future FFI loaders. The remaining same-substrate runtime
proof is live CUDA and Metal graph-kernel execution plus cross-substrate
tolerance.

## Cross-Substrate Tolerance Methodology

Cross-substrate equality is not bit-for-bit because float reductions
reassociate across vendor BLAS/DNN libraries and transcendentals (`exp`,
`log`, `sqrt`, `tanh`) are implemented differently by cuDNN, Metal, and
oneDNN, so per-tensor drift compounds through the forward + backward pass.

The tolerance methodology:

- Per layer family, a tolerance band is declared **in Haskell code** at
  `src/JitML/Engines/Tolerance.hs` as a `LayerFamilyTolerance` record
  (e.g., dense layer dot products are tighter than attention block
  outputs after softmax). The bands are calibrated from the public
  literature on cuDNN / Metal / oneDNN drift, not from an empirical
  per-substrate measurement on whichever host happened to write the
  fixture first.
- The `jitml-cross-backend` stanza (Sprint `12.6`) runs the canonical
  workloads on multiple substrates the host can exercise (subset), captures
  per-tensor outputs at fixed checkpoints, and asserts the L∞ drift fits
  inside the in-code band.
- A drift exceeding the tolerance band fails the stanza with a structured
  diagnostic naming the offending tensor, the layer, and the measured
  versus declared bound.
- Per-tensor empirical fixture files (e.g. `test/golden/cross-backend/<pair>/<tensor>.json`)
  are explicitly **not** committed. They would harden whichever host
  executed the calibration run into the repository as authoritative,
  giving a false sense of correctness while masking real drift on any
  substrate / toolchain pin the calibration host did not exercise.
  Widening a tolerance constant requires a code change with a Why
  justification; tightening is a free win and a code change.

## Determinism Caveats

- **TensorBoard byte stream is not part of any bit-determinism check.** TF's
  `Event` message carries `wall_time`; shard boundaries depend on wall-clock
  flush thresholds; writer metadata varies across writer-ids. The scalar
  values themselves at each `(tag, step)` *are* deterministic — the test is
  to decode two fresh runs, project each to `[(tag, step, value)]`, sort
  canonically, and assert equality between the two run-derived sequences
  (no committed reference shard).
- **Pulsar message metadata varies across runs** (timestamps, broker-assigned
  message ids). Determinism applies to the durable message **body** only.
- **Wall-clock benchmark numbers are not reproducible.** The bit-determinism
  contract is on visit counts, model parameters, training transcripts, and
  inference outputs — not throughput. Per [unit_testing_policy.md → Snapshot
  Tests and the Prohibition on Numerical Fixtures](unit_testing_policy.md#snapshot-tests-and-the-prohibition-on-numerical-fixtures),
  no `.txt` / `.json` files of hardcoded latency, env-steps/sec, or
  gradient-updates/sec are committed; perf regression is detected by
  on-host comparison against a recent baseline computed during the same
  CI run, not by a stored fixture. `JitML.Engines.Tuning.benchmarkPlan`
  makes the candidate knob list deterministic, and `selectMeasuredTuning`
  makes selection deterministic for a fixed measurement set.
  `TuningBenchmark` collects candidate measurements in plan order and records
  output digests alongside latency before `TuningStore` persists the selected
  `TuningChoice` by substrate and base hash. Its CUDA/Metal runner entrypoints
  currently preflight runtime availability and fail closed before live FFI
  measurement, so no unavailable hardware path fabricates a timing result.
  `TuningCache` loads the persisted choice before deriving the final runtime
  source and cache key. The eventual hardware timing loop may produce different
  measurements across machines, and that selected `TuningChoice` becomes an
  explicit cache-key input.

## Cross-References

- [../../README.md → Substrates and runtime modes](../../README.md#substrates-and-runtime-modes)
- [../../README.md → Bit-determinism contract](../../README.md#bit-determinism-contract)
- [jit_codegen_architecture.md](jit_codegen_architecture.md)
- [checkpoint_format.md](checkpoint_format.md)
- [../../DEVELOPMENT_PLAN/phase-7-jit-codegen-and-substrates.md](../../DEVELOPMENT_PLAN/phase-7-jit-codegen-and-substrates.md)
- [../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md](../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md)

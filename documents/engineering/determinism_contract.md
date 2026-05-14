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
modes](../README.md#substrates-and-runtime-modes), each substrate carries its
own floating-point determinism contract.

### `apple-silicon` (Metal)

- Metal compute kernels execute on the host GPU.
- Float-accumulation order is fixed by the kernel's reduction tree (no
  `-ffast-math`).
- RNG state lives in the host daemon (`Host + SelfInference`).
- Kernel-launch ordering is single-stream by default. Single MTLCommandQueue
  with FIFO ordering; explicit barriers prevent kernel reordering.
- **Tradeoff**: single-stream launch forfeits the multi-stream concurrency
  that hides launch latency at small batch sizes — the throughput cost is
  real and is the price of the bit-determinism contract.

### `linux-cpu` (oneDNN)

- oneDNN dispatches to a per-host vector ISA detected at JIT time
  (AVX2 baseline, AVX-512 detected and used when available).
- Reductions are blocked with a fixed block size so the accumulation tree is
  host-independent. The block size is part of `ToolchainFingerprint`; a
  block-size change invalidates the cache key.
- RNG state lives in the clustered service pod.

### `linux-cuda` (CUDA C + cuBLAS / cuDNN)

- CUDA kernels disable `--use_fast_math`.
- Per-block reductions use a deterministic warp-shuffle pattern.
- cuBLAS and cuDNN are pinned to deterministic algorithm selections via
  `cudnnSetConvolutionMathType` plus explicit algorithm-id pinning. The
  cuDNN algorithm-id selection is restricted to the deterministic-only set.
- RNG is the host's splitmix, never the GPU's curand.
- **Tradeoff**: cuDNN's deterministic convolution algorithms are typically
  20–50% slower than the non-deterministic defaults on training workloads;
  this is the price of the bit-determinism contract.

## RNG Split and Per-Experiment Seed Derivation

The master seed is declared in the experiment Dhall. Per-experiment seeds are
derived deterministically:

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

The JIT cache key is the four-tuple

```
sha256(canonical-cbor(KernelSpec) || kind || substrate || toolchain-fingerprint)
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
  `cabal.project` (LLVM, NVCC, Xcode/Metal, oneDNN) plus the auto-tune
  `TuningChoice` (Sprint `7.6`).

A change in any input invalidates the cache key, so a re-JIT is
substrate-explicit and toolchain-explicit.

## Engine Envelope

Every checkpoint manifest carries a typed `EngineEnvelope` block that captures
the substrate-specific reproducibility witnesses:

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
which step pulls a particular sample. The bit-equality golden anchor for
off-policy algorithms is therefore the **first-N-steps prefix** (default
`RL_STEPS / 10` per
[../../DEVELOPMENT_PLAN/system-components.md → POC Report-Card
Knobs](../../DEVELOPMENT_PLAN/system-components.md#poc-report-card-knobs)).

For on-policy algorithms (PPO, A2C, TRPO, MaskablePPO, RecurrentPPO),
full-run bit-equality holds.

For SL training, full-run bit-equality holds.

For AlphaZero self-play, per-game bit-equality holds (deterministic
stochasticity).

## Cross-Substrate Tolerance Methodology

Cross-substrate equality is not bit-for-bit because float reductions
reassociate across vendor BLAS/DNN libraries and transcendentals (`exp`,
`log`, `sqrt`, `tanh`) are implemented differently by cuDNN, Metal, and
oneDNN, so per-tensor drift compounds through the forward + backward pass.

The tolerance methodology:

- Per layer family, an empirically-calibrated per-tensor tolerance band is
  declared (e.g., dense layer dot products are tighter than attention block
  outputs after softmax).
- The `jitml-cross-backend` stanza (Sprint `12.6`) runs the canonical
  workloads on multiple substrates the host can exercise (subset), captures
  per-tensor outputs at fixed checkpoints, and asserts the L∞ drift fits
  inside the band.
- A drift exceeding the tolerance band fails the stanza with a structured
  diagnostic naming the offending tensor, the layer, and the measured
  versus declared bound.
- The bands are pinned in `cabal.project` once empirically calibrated by the
  initial Phase `12` cross-cluster runs.

## Determinism Caveats

- **TensorBoard byte stream is not part of any bit-determinism golden.** TF's
  `Event` message carries `wall_time`; shard boundaries depend on wall-clock
  flush thresholds; writer metadata varies across writer-ids. The scalar
  values themselves at each `(tag, step)` *are* deterministic — the test is
  to decode, project to `[(tag, step, value)]`, sort canonically, assert
  equality.
- **Pulsar message metadata varies across runs** (timestamps, broker-assigned
  message ids). Determinism applies to the durable message **body** only.
- **Wall-clock benchmark numbers are not reproducible.** The bit-determinism
  contract is on visit counts, model parameters, training transcripts, and
  inference outputs — not throughput.

## Cross-References

- [../README.md → Substrates and runtime modes](../README.md#substrates-and-runtime-modes)
- [../README.md → Bit-determinism contract](../README.md#bit-determinism-contract)
- [jit_codegen_architecture.md](jit_codegen_architecture.md)
- [checkpoint_format.md](checkpoint_format.md)
- [../../DEVELOPMENT_PLAN/phase-7-jit-codegen-and-substrates.md](../../DEVELOPMENT_PLAN/phase-7-jit-codegen-and-substrates.md)
- [../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md](../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md)

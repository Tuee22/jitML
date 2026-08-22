# Phase 267: GPU Performance and Persistent Device Buffers

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: GPU Performance and Persistent Device Buffers. Single-session phase migrated from legacy Sprint 29.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** (2026-08-22). The `linux-cuda` lane is not merely correct but
**performant**: `jitml internal benchmark-product-row-wall-clock` reports
`rows=55`, `status=PASS`, with every one of the 55 product rows strictly faster
on `linux-cuda` than on `linux-cpu` — speedups from **2.142558x** to **4.708x**,
mean **3.600x**, no per-row exemption. That discharges
[Exit Definition](README.md#exit-definition) item `29`, and the committed per-row
timing table in
[`attestations/linux-cuda-report-card.md`](attestations/linux-cuda-report-card.md)
records both substrates' measured wall-clock.

The persistent device weight buffers this phase built are real and retained, but
they were not what item `29` was blocked on. The binding cost was in the shared
host path rather than in the kernels: `JitML.Engines.Loader.ensureKernelArtifact`
runs on **every** device operation, not only on a cache miss, so the artifact
toolchain probe forked `nvcc --version` once per kernel launch — **20,692**
spawns in 60 s of PPO rollout, none of them a compile. A `linux-cuda` lane that
pays a process fork per launch is slower than the host tape no matter how good
its kernels are, which is why end-to-end training was the *slower* lane. With the
probe resolved once per substrate per process, `jitml rl train` on PPO/cartpole
measures **82 s** on `linux-cuda` against **192 s** on `linux-cpu` (**2.34x**).

### Historical Phase State

> ⏸️ **Blocked** by Sprint `266.1`. The persistent device weight buffers this phase
built are real and retained. What it cannot hold is the every-row performance
obligation it owns: its evidence rests on a `55 / 55` publisher run whose counts
Phase `266` records as withdrawn, so there is no attested row-complete cohort to
time until Sprint `266.1` produces one. The 2026-07-10 timing table remains
historical evidence for the surface it exercised.

> ⏸️ **Blocked** (reopened 2026-08-16 under standards rule `C`) by the withdrawn
row-complete counts and the 2026-08-16 measured run's `eligible: 50`,
`errors: 5`. Phase `265` re-closed on 2026-08-18 at `eligible: 55`, `errors: 0`.

## Sprint 267.1: GPU Performance and Persistent Device Buffers [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Engines/Loader.hs`, `src/JitML/Codegen/MlpCuda.hs`, `src/JitML/Numerics/MlpCuda.hs`, `src/JitML/App.hs`, `DEVELOPMENT_PLAN/attestations/linux-cuda-report-card.md`
**Docs updated**: `../documents/engineering/jit_codegen_architecture.md`,
`../documents/engineering/numerical_core.md`

### Objective

The `linux-cuda` lane is not merely correct but **performant**: on the
persistent-buffer, vectorized-env regime it outperforms `linux-cpu` on every
product row, so the accelerator lane is a real speedup rather than a
slower-but-correct alternative.

### Deliverables

- Persistent CUDA device weight buffers in `src/JitML/Codegen/MlpCuda.hs` hoist
  the per-call `cudaMalloc` plus host-to-device weight copy out of the per-batch
  kernel path: weights upload once per fixed-parameter phase and are reused
  across every batch and vectorized-env step, so the `jitml_mlp_forward` /
  `_batch` / `_grad` hand-written elementwise kernels launch against resident
  device buffers instead of re-staging weights on each call.
- Vectorized-env CUDA throughput batches the ~16 parallel env instances through
  the network in a single device call per step, amortizing kernel-launch
  overhead across the batch.
- A committed per-row `linux-cuda`-vs-`linux-cpu` wall-clock timing table in the
  `linux-cuda` report card (`DEVELOPMENT_PLAN/attestations/linux-cuda-report-card.md`),
  one entry per product row, recording both substrates' measured wall-clock.
- The CUDA batch-gradient generator uses one thread per weight element for
  `gW1`/`gW2` plus separate bias kernels, preserving deterministic per-thread
  batch reductions while keeping tiny-output rows fast enough to clear the
  strict every-row speedup gate.

### Validation

Exit-Definition item #29 (**STRICT, every-row**): every one of the 55 product
rows' `linux-cuda` wall-clock is strictly less than its `linux-cpu` wall-clock,
recorded in the committed per-row timing table in the `linux-cuda` attestation.
Validation stays single accelerator — the CPU baseline is `linux-cpu`, not an
accelerator, so there is no dual-accelerator gate: `linux-cuda` plus `linux-cpu`,
never `apple-silicon`.

2026-08-22 closing validation:

| Gate | Result |
|---|---|
| `jitml internal benchmark-product-row-wall-clock` | exit `0` — `rows=55`, `status=PASS`; min speedup **2.142558x**, max **4.708x**, mean **3.600x** |
| `jitml test jitml-backends --linux-cuda` | **28 / 28** PASS |
| `jitml rl train experiments/cartpole.dhall` (PPO/cartpole, end-to-end) | `linux-cuda` **82 s** vs `linux-cpu` **192 s** (**2.34x**) |

The committed table in
[`attestations/linux-cuda-report-card.md`](attestations/linux-cuda-report-card.md)
records each row's `linux-cpu` seconds, `linux-cuda` seconds, and speedup from
that run. The gate is strict and every-row: the command exits non-zero if any
single row's `linux-cuda` wall-clock is not strictly less than its `linux-cpu`
wall-clock, so `status=PASS` is the per-row claim, not an average.

### Historical Validation

2026-07-10 status: persistent CUDA MLP weight buffers are implemented and covered
by `jitml-backends --linux-cuda` (**22 / 22**), and the full CUDA publisher
passes **55 / 55**. The full ProductRow wall-clock timing gate passed with
**55 / 55** rows faster on CUDA using:

```bash
docker compose run --rm jitml-cuda sh -lc 'cabal run -fcuda exe:jitml -- internal benchmark-product-row-wall-clock'
docker compose run --rm jitml-cuda cabal run -fcuda exe:jitml -- test jitml-backends --linux-cuda
```

The committed table in
`DEVELOPMENT_PLAN/attestations/linux-cuda-report-card.md` records each row's
`linux-cpu` seconds, `linux-cuda` seconds, and speedup. The post-update backend
gate passed **22 / 22**, including the source guard for persistent device buffers
and the per-weight CUDA MLP batch-gradient kernels.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

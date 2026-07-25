# Phase 183: Re-validate the linux-cuda lane runs for real with the skip guards removed

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Re-validate the linux-cuda lane runs for real with the skip guards removed. Single-session phase migrated from legacy Sprint 15.16 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 183.1: Re-validate the linux-cuda lane runs for real with the skip guards removed [✅ Done]

**Status**: Done (closed 2026-06-09 on the NVIDIA GeForce RTX 5090 host, UUID `GPU-e764ef97-32d7-4981-c348-029983c64073`)
**Implementation**: `test/cross-backend/Main.hs`
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/unit_testing_policy.md`

### Objective

With the `probeCudaRuntime` / `cudaRuntimeAvailable` and
`cublasBindingsCompiledIn` / `cudnnBindingsCompiledIn` skip guards removed from
`test/cross-backend/Main.hs`, re-validate that the linux-cuda
within-substrate cases run **for real** in the `jitml-cuda` GPU container: the
nvcc compile + FFI load path, the warp-shuffle reduction kernel, kernel
bit-equality across repeated runs, the MLP / RL / AlphaZero device-determinism
cases, and the cuBLAS / cuDNN version/binding init. A missing GPU now **fails**,
it does not skip. Within-substrate bit-for-bit reproducibility is the retained
contract (across substrates carries **no** parity guarantee); CUDA is **not**
removed.

### Deliverables

- The linux-cuda lane (`-p linux-cuda`) of `jitml-cross-backend` runs every
  within-substrate CUDA case as a real PASS with **no skip-sentinels** — the
  removed guards mean a missing `nvcc` / GPU / cuBLAS / cuDNN toolchain now
  produces a hard FAIL.
- The within-substrate bit-for-bit reproducibility cases (kernel bit-equality,
  MLP / RL / AlphaZero device-determinism) stay green under the guards-removed
  lane.

### Validation

1. `docker compose run --rm jitml-cuda cabal test -fcuda jitml-cross-backend --test-options '-p linux-cuda'`
   runs every linux-cuda case as a real PASS (no skip-sentinels) in the
   GPU-attached `jitml-cuda` container; absence of the GPU/toolchain fails the
   lane rather than skipping it. (`-fcuda` is the `cabal` build flag that
   compiles the real cuBLAS / cuDNN bindings — off by default to keep the
   headless `jitml` baseline warning-clean — so the GPU lane is driven through
   the GPU container's `cabal test -fcuda` form per the `jitml-cuda`
   compose-service contract, not through the flag-free `jitml test` orchestrator
   that owns the apple-silicon / linux-cpu lanes.)

### GPU Re-validation Evidence (2026-06-09, RTX 5090)

The sole remaining obligation — the live `linux-cuda` lane on real NVIDIA
hardware — was exercised and **passed** on the NVIDIA GeForce RTX 5090 host
(UUID `GPU-e764ef97-32d7-4981-c348-029983c64073`, CUDA 12.8, Ubuntu 24.04,
Docker 29.5.1). The lane was run in the GPU-attached `jitml-cuda` compose
service (which exposes the host GPU via the NVIDIA Container Runtime; host
`nvcc` is never installed, see [../CLAUDE.md](../CLAUDE.md)). `nvidia-smi -L`
inside the service reported the RTX 5090 (matching UUID) before the run.

The `-fcuda` build flag is a `cabal` build flag (it sets
`-DJITML_CUDA_BINDINGS=1`, compiling the real cuBLAS / cuDNN Haskell bindings;
it is off by default so the headless `jitml` baseline stays warning-clean and
CUDA-free), so the lane is driven through the GPU container's `cabal test
-fcuda` form — the same methodology every historical CUDA evidence line in this
plan and the `jitml-cuda` compose-service comment use — rather than through the
flag-free `jitml test` orchestrator that owns the apple-silicon / linux-cpu
lanes:

```
docker compose run --rm jitml-cuda cabal test -fcuda jitml-cross-backend --test-options '-p linux-cuda'
```

Result: **All 19 tests passed (12.26s)**, `Test suite jitml-cross-backend:
PASS`, with **no skip-sentinels** — every selected case is a real device PASS:
the nvcc generated-kernel compile + FFI load, the warp-shuffle reduction
kernel, kernel bit-equality across repeated runs, the weighted Dense2D device
GEMM, cuBLAS and cuDNN binding version init, the benchmark candidate runner, MLP
forward / backward / batched-gradient kernels, the PPO / DQN / QR-DQN / HER /
DDPG batched device trainers, and AlphaZero `PolicyValueNet` device training.
With the `cublasBindingsCompiledIn` / `cudnnBindingsCompiledIn` guards removed, a
build without `-fcuda` would now hard-FAIL the cuBLAS / cuDNN cases
(`verifyCublasRuntime` / `verifyCudnnRuntime` return `Left (-2)` when
`JITML_CUDA_BINDINGS` is absent) rather than skip them — the fail-by-design
contract holds.

### Remaining Work

- None. The `linux-cuda` lane was re-validated for real on the RTX 5090 on
  2026-06-09 (19 / 19, no skip-sentinels); the skip-guard removal is complete
  and the sprint is `✅ Done`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

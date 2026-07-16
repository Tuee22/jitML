# Phase 29: linux-cuda Product Lane

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-28-per-model-integration-and-e2e.md](phase-28-per-model-integration-and-e2e.md), [phase-30-apple-silicon-product-lane.md](phase-30-apple-silicon-product-lane.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/jit_codegen_architecture.md](../documents/engineering/jit_codegen_architecture.md), [../documents/engineering/numerical_core.md](../documents/engineering/numerical_core.md)
**Generated sections**: none

> **Purpose**: Validate the row-complete product matrix on the real
> `linux-cuda` substrate, with generated CUDA family kernels invoking cuBLAS and
> cuDNN on the device path, without requiring Apple Silicon in the same phase.

## Phase State

⏸️ **Blocked** (reopened 2026-07-12 for Sprint `29.5`). The existing
`linux-cuda` attestation predates the validated-plan and exact-evidence contract,
so it cannot close the expanded Exit Definition. Sprint `29.5` is blocked by
Sprint `28.4`. Sprints `29.1`–`29.4` remain Done on their retained CUDA kernel,
device-evidence, integration, and performance surfaces.

**Historical retained closure.** ✅ **Done** (2026-07-10). The prior Docker-GPU blocker is resolved: the current
RTX 5090 host exposes the `nvidia` container runtime, `jitml-cuda` sees the GPU,
and Sprint `29.1` validated for real. The current backend gate
`docker compose run --rm jitml-cuda jitml test jitml-backends --linux-cuda`
passes **22 / 22**, including real cuBLAS/cuDNN execution and the Phase `29.4`
source guard for persistent CUDA MLP weight buffers.

The Phase `24` / `25` / `33` convergence blockers have been remediated on the
`linux-cpu` truth gates: `jitml-sl-canonicals` **31 / 31**,
`jitml-rl-canonicals` **39 / 39**, `jitml-negative-controls` **3 / 3**,
`jitml-model-convergence` **111 / 111**, `jitml-unit` **278 / 278**, and the
row-keyed integration matrix **137 / 137** passed during the 2026-07-10
remediation. On the CUDA publisher path, the missing `HER/goal-reaching`
multi-metric witness was fixed, `fashion-mnist-resnet` now publishes under the
row-specific LR default (`test_accuracy=0.826`), and the expensive compact
supervised rows `cifar10-resnet20`, `cifar10-resnet56`, `cifar10-vit`, and
`tiny-imagenet-resnet50` publish with row-specific real budgets instead of the
unbounded heavy defaults.

Sprints `29.2` and `29.3` are **Done**. The 2026-07-10 current-source CUDA publisher work
fixed the known supervised failure (`fashion-mnist-resnet`), validated the
compact expensive supervised defaults, added CUDA MLP cache eviction and
process-local kernel-library reuse so long publisher runs no longer grow GPU
memory toward `cudaMalloc` OOM, narrowed the last calibrated `PPO/key-door-grid`
publisher row to **1 / 1** eligible with **0** errors, reran the full
current-source CUDA publisher to **55 / 55** eligible rows with **0** unsupported
rows and **0** errors, and passed the row-keyed ProductRow integration matrix
with **56 / 56** tests. Sprint `29.3` then passed `jitml test all
--linux-cuda` with **10 / 10** stanzas, standalone CUDA e2e with **27 / 27**
tests, and the live CUDA e2e gate with **71 / 71** Playwright tests plus
**27 / 27** Haskell e2e tests at edge `:9092`. Sprint `29.4` then closed the
strict every-row `linux-cuda` < `linux-cpu` timing obligation: the committed
wall-clock table records **55 / 55** ProductRows faster on CUDA, and the
post-update `jitml-backends --linux-cuda` gate passes **22 / 22**.

**Validation substrate**: `linux-cpu` plus `linux-cuda`; no `apple-silicon`
validation is part of this phase.

Sprint `29.4` (added in this expansion) extends this phase's Exit Definition
beyond correctness to **GPU performance**: the `linux-cuda` lane must outperform
`linux-cpu` on every product row (Exit-Definition item #29), not merely converge.

## Objective

The CUDA codegen path emits real generated CUDA source for the product family
surface. Dense and attention-family kernels call `cublasSgemm`, Conv2D and
Conv3D call `cudnnConvolutionForward` through deterministic cuDNN descriptors,
and BatchNorm/LayerNorm call cuDNN batch-normalization descriptor APIs. The
product training path records real CUDA device evidence through the CUDA
`MlpDevice`, publishes completed checkpoints for every ProductRow, and drives
the row-keyed integration, e2e, and live Playwright product matrix on the
published CUDA edge. Runtime absence fails up front; CUDA-supported rows do not
pass vacuously.

## Sprint 29.1: Real cuDNN/cuBLAS Kernels [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Codegen/Cuda.hs`, `src/JitML/Engines/CudaLocal.hs`, `src/JitML/Engines/CublasBindings.hs`, `src/JitML/Engines/CudnnBindings.hs`, `test/backends/Main.hs`
**Docs updated**: `../documents/engineering/jit_codegen_architecture.md`, `../documents/engineering/numerical_core.md`

### Objective

`src/JitML/Codegen/Cuda.hs` renders generated CUDA family sources whose
operation-critical bodies call cuBLAS/cuDNN instead of carrying product-reachable
identity-copy placeholder bodies for Dense, Conv2D, Conv3D, BatchNorm,
LayerNorm, and MHA. The generated source owns the native CUDA/cuBLAS/cuDNN
handles inside the compiled artifact, while the Haskell binding modules keep the
typed compile/runtime probes that fail closed when the CUDA cabal flag or runtime
is absent.

### Deliverables

- Dense2D and MHA generated CUDA bodies route the flat-vector GEMM ABI through
  deterministic `cublasSgemm` calls. MHA chains Q/K projections, a CUDA
  score-product kernel, and an output projection through the same cuBLAS helper.
- Conv2D and Conv3D generated CUDA bodies route the weighted and unweighted
  flat-vector family ABI through cuDNN tensor/filter/convolution descriptors and
  `cudnnConvolutionForward` with
  `CUDNN_CONVOLUTION_FWD_ALGO_IMPLICIT_PRECOMP_GEMM`.
- BatchNorm and LayerNorm generated CUDA bodies route through cuDNN
  batch-normalization descriptors; LayerNorm uses per-activation mode and
  generated mean/variance parameter filling.
- Embedding keeps its explicit CUDA table-lookup kernel because cuBLAS/cuDNN do
  not provide an embedding lookup primitive; the unweighted embedding case copies
  indices through by design.
- The old `scaffold` comments are removed from generated CUDA source, and the
  Sprint `29.1` future-owned CUDA scaffold entries are removed from
  `ProductTruth`.
- `test/backends/Main.hs` asserts the rendered CUDA source calls
  `cublasSgemm`, `cudnnConvolutionForward`, cuDNN tensor descriptors, and cuDNN
  normalization APIs, and `jitml-backends --linux-cuda` compiles and executes
  the generated source on the attached GPU.

### Validation

```bash
docker compose run --rm jitml-cuda jitml test jitml-backends --linux-cuda
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

2026-07-10 live validation: `docker compose run --rm jitml-cuda jitml test
jitml-backends --linux-cuda` passed **22 / 22** on the attached RTX 5090,
including real `cublasSgemm` / `cudnnConvolutionForward` execution,
bit-deterministic device GEMM, nvcc + FFI compile/run, and the persistent MLP
weight-buffer source guard.

### Closure Evidence

- **Closed Exit-Definition obligation (real device cuBLAS/cuDNN kernels).** The
  Dense/MHA/Conv2D/Conv3D/BatchNorm/LayerNorm generated CUDA bodies must call
  `cublasSgemm` / `cudnnConvolutionForward` and run real GEMM/convolution on the
  attached GPU for every CUDA-supported product row, and the
  `CublasBindings.hs` / `CudnnBindings.hs` probes must be live on that path
  instead of dead imports — a rendered-source text match must not stand in for
  device execution.
- **Negative-control validation that closes it.** Re-run
  `docker compose run --rm jitml-cuda jitml test jitml-backends --linux-cuda`
  gated by the
  [`jitml-negative-controls`](phase-32-external-truth-realness-harness.md)
  differential that rejects an identity-copy result as cuBLAS/cuDNN evidence, so
  a row cannot pass on rendered-source text alone. Validation stays single
  accelerator: `linux-cuda` plus `linux-cpu`, never `apple-silicon`.

## Sprint 29.2: CUDA Row Device Evidence [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Product/Matrix.hs`, `src/JitML/App.hs`, `test/backends/Main.hs`, `test/integration/Main.hs`
**Docs updated**: `../documents/engineering/jit_codegen_architecture.md`, `../documents/engineering/unit_testing_policy.md`

### Objective

Every CUDA-supported product row records real `linux-cuda` device evidence:
runtime probe, generated-source compile/load/launch where applicable, and
substrate-backed learned-state updates through the CUDA device path. Missing
CUDA runtime, driver, or GPU availability fails the lane before row evidence can
be minted.

### Deliverables

- The live CUDA preflight proved Docker exposed the `nvidia` runtime and the RTX
  5090 GPU before any row validation ran.
- All 12 canonical dataset artifacts were uploaded through
  `jitml internal upload-dataset` and SHA-verified against
  `JitML.SL.Dataset.canonicalArtifactSha256For` before supervised rows trained.
- `jitml internal train-and-publish-product-rows --linux-cuda` produced
  inference-eligible artifacts for all **55 / 55** ProductRows on the current
  source after the CUDA publisher memory and convergence calibrations.
- The row-keyed integration matrix consumed the published
  `CompletedTraining` manifests and failed closed before this sprint whenever a
  required product-row checkpoint pointer or live cluster publication was absent.

### Validation

```bash
docker compose run --rm jitml-cuda jitml test jitml-backends --linux-cuda
docker compose run --rm jitml-cuda cabal run -fcuda exe:jitml -- internal train-and-publish-product-rows --linux-cuda
docker compose run --rm jitml-cuda jitml test jitml-integration --linux-cuda
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

2026-07-10 status: Sprint `29.1` is live and passing on the RTX 5090. Focused
current-source CUDA publisher runs validated the missing/failing supervised rows:
`fashion-mnist-resnet` publishes with `test_accuracy=0.826`, and the compact
real-budget rows `cifar10-resnet20`, `cifar10-resnet56`, `cifar10-vit`, and
`tiny-imagenet-resnet50` publish with **4 / 4** eligible. CUDA publisher memory
growth was fixed by evicting cached MLP device weights on allocation pressure and
reusing loaded kernel libraries for the process lifetime; the post-fix narrowed
`PPO/key-door-grid` publisher run passed with `rows: 1`, `eligible: 1`,
`unsupported: 0`, and `errors: 0`. The full current-source CUDA publisher then
passed with `rows: 55`, `eligible: 55`, `unsupported: 0`, and `errors: 0`.
The row-keyed ProductRow integration matrix over the refreshed CUDA checkpoint
pointers passed with **56 / 56** tests using:

```bash
docker compose run --rm jitml-cuda jitml test jitml-integration --linux-cuda --test-options '-p ProductRow --hide-successes --color=never'
```

### Closure Evidence

- **Closed Exit-Definition obligation (real per-row CUDA device evidence).** Every
  CUDA-supported product row must record real `linux-cuda` device evidence backed
  by a measured convergence metric that clears an external literature bar, not an
  eligibility flag minted from a tautological gate, an expert-controller reward,
  or a residual-MLP stand-in.
- **Negative-control validation that closes it.** After Phases `19`–`28`
  re-close, re-run
  `docker compose run --rm jitml-cuda jitml internal train-and-publish-product-rows --linux-cuda`
  and gate each row on the
  [`jitml-negative-controls`](phase-32-external-truth-realness-harness.md) suite
  (which rejects an under-target run) and the
  [`jitml-model-convergence`](phase-33-per-model-convergence-and-inference-tests.md)
  case that trains the CUDA-supported row from a real random init through the
  production path. Validation stays single accelerator: `linux-cuda` plus
  `linux-cpu`, never `apple-silicon`.

## Sprint 29.3: CUDA Integration, E2E, and Attestation [✅ Done]

**Status**: Done
**Implementation**: `test/integration/Main.hs`, `test/e2e/Main.hs`, `playwright/jitml-demo.spec.ts`, `DEVELOPMENT_PLAN/attestations/`
**Docs updated**: `../documents/engineering/unit_testing_policy.md`, `../documents/engineering/purescript_frontend.md`, `DEVELOPMENT_PLAN/attestations/linux-cuda-report-card.md`

### Objective

`jitml test all --linux-cuda` runs every CUDA-supported product row for real
through the training, checkpoint, integration, and e2e paths. Live Playwright
hits the CUDA edge and renders row-specific trained artifacts from the published
checkpoint list, and the refreshed `linux-cuda` attestation records the
row-complete lane evidence.

### Deliverables

- `jitml test all --linux-cuda` passed every CUDA-supported product row through
  integration/e2e evidence, including the live WorkflowMatrix and the row-keyed
  ProductRow integration cases.
- `jitml test jitml-e2e --live --linux-cuda` selected the existing CUDA
  publication at edge `:9092`, ran the Haskell e2e stanza, and then ran the live
  Playwright product matrix against that edge.
- Live Playwright rendered every generated ProductRow artifact selector as
  eligible: **71 / 71** browser tests passed, including **55 / 55** row-specific
  `e2e.product.*` cases.
- The refreshed CUDA report card in
  `DEVELOPMENT_PLAN/attestations/linux-cuda-report-card.md` records the 2026-07-10
  Phase `29` validation.

### Validation

```bash
docker compose run --rm jitml-cuda jitml test all --linux-cuda
docker compose run --rm jitml-cuda jitml test jitml-e2e --linux-cuda
docker compose run --rm jitml-cuda jitml test jitml-e2e --live --linux-cuda
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

2026-07-10 validation passed on the current source: `jitml test all
--linux-cuda` passed **10 / 10** stanzas (`jitml-unit` **278 / 278**,
`jitml-integration` **137 / 137**, `jitml-sl-canonicals` **31 / 31**,
`jitml-rl-canonicals` **39 / 39**, `jitml-hyperparameter` **19 / 19**,
`jitml-backends` **22 / 22**, `jitml-daemon-lifecycle` **32 / 32**,
`jitml-e2e` **27 / 27**, `jitml-negative-controls` **3 / 3**, and
`jitml-model-convergence` **111 / 111**). Standalone CUDA e2e then passed
**27 / 27**. The live CUDA e2e gate selected the existing CUDA publication at
edge `:9092`, ran the checkpoint-backed Playwright product matrix with
**71 / 71** browser tests, and passed the Haskell e2e stanza with **27 / 27**.

### Closure Evidence

- **Closed Exit-Definition obligation (row-complete CUDA integration/e2e/
  attestation).** `jitml test all --linux-cuda` and the live Playwright product
  matrix must pass for every CUDA-supported row against checkpoints whose per-row
  convergence is really measured, and the refreshed `linux-cuda` attestation must
  record that real evidence rather than the withdrawn `55 / 55` / `71 / 71`
  counts.
- **Negative-control validation that closes it.** After Phases `19`–`28` re-close
  and Sprint `29.2` re-validates, re-run
  `docker compose run --rm jitml-cuda jitml test all --linux-cuda` and
  `docker compose run --rm jitml-cuda jitml test jitml-e2e --live --linux-cuda`,
  gated by the
  [`jitml-negative-controls`](phase-32-external-truth-realness-harness.md) and
  [`jitml-model-convergence`](phase-33-per-model-convergence-and-inference-tests.md)
  suites, and re-commit the attestation only after they pass. Validation stays
  single accelerator: `linux-cuda` plus `linux-cpu`, never `apple-silicon`.

## Sprint 29.4: GPU Performance and Persistent Device Buffers [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Codegen/MlpCuda.hs`, `src/JitML/Numerics/MlpCuda.hs`, `src/JitML/App.hs`, `DEVELOPMENT_PLAN/attestations/linux-cuda-report-card.md`
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

## Sprint 29.5: Contract-Driven CUDA Lane Revalidation [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Test/RunContract.hs`,
`src/JitML/Test/Report.hs`, `test/integration/Main.hs`,
`DEVELOPMENT_PLAN/attestations/linux-cuda-report-card.md`
**Blocked by**: Sprint `28.4`
**Docs to update**: `../README.md`,
`../documents/engineering/product_completion_contract.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/run_contract.md`, `system-components.md`

### Objective

Revalidate the full row-complete workflow contract on a real `linux-cuda` host
and replace the lane fragment with journal-derived evidence. This sprint owns
the CUDA-lane portions of [Exit Definition](README.md#exit-definition) items
`31`, `32`, and `34` while preserving the existing item `29` performance bar.
The binding design is
[README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Run every supported CUDA product scenario through the same validated plan,
  receipt-bound consumer, exact evidence reducer, and scoped lifecycle used by
  the `linux-cpu` lane.
- Prove each completed row journal carries the CUDA substrate/device witness,
  exact terminal evidence, trained artifact hash, and measured inference result.
- Re-run the existing backend, publisher, integration, e2e, negative-control,
  model-convergence, and every-row CUDA-vs-CPU performance gates on the real GPU.
- Replace the committed `linux-cuda` fragment only after all scenarios complete;
  retain explicit failed/not-run entries rather than fabricating pass cells.
- Record cleanup and diagnostic evidence for the full bootstrap/test/down
  lifecycle without requiring Apple Silicon in this phase.

### Validation

```bash
./bootstrap/linux-cuda.sh up
./bootstrap/linux-cuda.sh test
./bootstrap/linux-cuda.sh down
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Blocked until Sprint `28.4` closes the contract-driven `linux-cpu` row matrix.
- Execute the real CUDA lifecycle and regenerate the lane journal/attestation.
- Reconfirm the existing strict per-row GPU-performance criterion before
  returning this phase to Done.

## Documentation Requirements

**Engineering docs updated:**
- `documents/engineering/run_contract.md` — contract-driven CUDA lane journals
  and scoped lifecycle evidence.
- `documents/engineering/jit_codegen_architecture.md` — records the Phase `29`
  cuBLAS/cuDNN generated CUDA family surface and row-complete CUDA validation.
- `documents/engineering/numerical_core.md` — records the CUDA family kernels and
  CUDA device-backed product row evidence.
- `documents/engineering/unit_testing_policy.md` — records the Phase `29`
  `jitml-backends`, integration, e2e, and live Playwright coverage.
- `documents/engineering/purescript_frontend.md` — records CUDA-edge Playwright
  coverage of row-specific trained artifacts.

**Product docs to update after Sprint `29.5`:**
- `README.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`,
  and `DEVELOPMENT_PLAN/system-components.md` retain the dated Sprint
  `29.1`–`29.4` runtime/performance evidence while recording Phase `29` as
  Blocked until the refreshed CUDA scenario journal is emitted and validated.
- On closure, replace the blocked wording with the journal identity, exact
  ProductRow/PlanId coverage, real CUDA substrate evidence, and validation
  result produced by the shared workflow interpreter.

**Cross-references updated:**
- The refreshed `linux-cuda` attestation is linked from Phase `31` as a required
  input to final aggregation.

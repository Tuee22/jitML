# Phase 29: linux-cuda Product Lane

**Status**: Blocked
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-28-per-model-integration-and-e2e.md](phase-28-per-model-integration-and-e2e.md), [phase-30-apple-silicon-product-lane.md](phase-30-apple-silicon-product-lane.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/jit_codegen_architecture.md](../documents/engineering/jit_codegen_architecture.md), [../documents/engineering/numerical_core.md](../documents/engineering/numerical_core.md)
**Generated sections**: none

> **Purpose**: Validate the row-complete product matrix on the real
> `linux-cuda` substrate, with generated CUDA family kernels invoking cuBLAS and
> cuDNN on the device path, without requiring Apple Silicon in the same phase.

## Phase State

⏸️ **Blocked** (2026-07-07). The prior Docker-GPU blocker is **resolved**: on the
current RTX 5090 host the `nvidia` container runtime is registered and the
`jitml-cuda` compose service sees the GPU, so **Sprint `29.1` validated for
real** — `jitml test jitml-backends --linux-cuda` passed **21 / 21** on the
attached GPU (real `cublasSgemm`/`cudnnConvolutionForward`, bit-deterministic
device GEMM, nvcc + FFI compile/run), with `jitml-unit --linux-cpu` **277 / 277**
and `check-code` **ok**. The live CUDA cluster came up (edge `:9092`) and all 12
canonical datasets were SHA-verified into MinIO.

Running the real `jitml internal train-and-publish-product-rows --linux-cuda`
exposed the true blocker: **the product-row models did not converge to their
literature-anchored bars** — the first honest run reported **eligible 23,
errors 32**; a prior remediation reached **30 / 55**. This contradicts the
"converged" status of Phases `25` (real RL) and `33` (per-model convergence),
which remain `Active` (standards rule N).

**2026-07-07 remediation (this session).** A numerical audit root-caused the
largest gap: the generated CUDA MLP kernels left nvcc **FMA contraction**
(`--fmad`) enabled while the oneDNN/CPU build uses separate multiply-then-add with
fixed reduction order, so identical code and seed converged materially worse on
`linux-cuda` (PPO/cartpole **450** on CPU vs **286** on CUDA). Adding
`--fmad=false` to the CUDA nvcc command plus the three JIT-cache fingerprints
(`Engine.hs` / `CudaLocal.hs` / `MlpCuda.hs`, so the kernels recompile) makes the
substrates track; verified live on the RTX 5090: PPO/cartpole and
PPO/lunar-lander went error → **eligible**. Additional real fixes landed and were
validated: potential-based reward shaping (`JitML.RL.RewardShaping`,
training-only, scoped to mountain-car/acrobot) fixing PPO/acrobot; a QR-DQN
retune fixing QR-DQN/cartpole; unified cross-substrate on-policy tuning;
mountain-car exploring starts + observation normalization; a deep-SL
residual-scale increase that passed `cifar10-resnet20` on the GPU; and a
board-scaled AlphaZero arena search with an odd arena-game count that resolves a
hex all-draw-sentinel false positive. `jitml-model-convergence` and
`jitml-negative-controls` pass and `cabal build all` is clean.

**Remaining unconverged rows** (genuinely hard, owned by Phases `25` / `33`): the
on-policy mountain-car cohort (PPO / A2C / TRPO / MaskablePPO / RecurrentPPO — a
sparse-reward exploration wall that potential shaping provably cannot address
on-policy, δ_shaped ≡ δ_true once the value baseline converges); DQN / QR-DQN
mountain-car (−159 / −153, marginal); TRPO/lunar-lander (the crude diagonal-Fisher
natural gradient diverges); SAC/pendulum (swing-up needs temporally-correlated
exploration); and the deep-SL `cifar100-wide-resnet` / `fashion-mnist-resnet`
rows (the executed residual stack is an un-normalized bag-of-patches with no
cross-patch mixing — fashion caps at ~0.60 vs a 0.85 bar). A full `linux-cuda`
`train-and-publish` on this session's fixes is a multi-hour job (per-row GPU RL
cost is dominated by tiny-MLP kernel-launch overhead plus the single-threaded env
simulator) and was in progress at this checkpoint with the SL / on-policy /
off-policy / continuous families recovered. **55 / 55 is not yet reached.**

**Blocked by**: Phases `25` / `33` producing genuinely-converging product rows
(real RL/deep-SL/AlphaZero implementations), then a fresh full real `linux-cuda`
`train-and-publish` + `test all` pass. The GPU/runtime prerequisite is met.

**Validation substrate**: `linux-cpu` plus `linux-cuda`; no `apple-silicon`
validation is part of this phase.

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

## Sprint 29.1: Real cuDNN/cuBLAS Kernels [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: real `linux-cuda` backend execution on a Docker-visible NVIDIA GPU.
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

2026-07-06 source-side validation: `docker compose run --rm jitml cabal build
test:jitml-backends test:jitml-negative-controls` passed; `docker compose run
--rm jitml cabal test jitml-negative-controls --test-options='--color=never
--hide-successes' --test-show-details=direct` passed **3 / 3**; focused
`jitml-backends` generated CUDA source validation passed **1 / 1**. Live
`linux-cuda` validation remains blocked because Docker did not expose a GPU
runtime to the `jitml-cuda` service on this host.

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

## Sprint 29.2: CUDA Row Device Evidence [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `29.1` live CUDA execution and a real `linux-cuda`
train/publish run on a Docker-visible NVIDIA GPU.
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
  inference-eligible artifacts for all **55 / 55** ProductRows: the first
  publisher pass produced **44 / 44** non-supervised rows after cluster bootstrap,
  and the filtered supervised pass produced **11 / 11** rows after canonical
  dataset staging.
- The row-keyed integration matrix consumed the published
  `CompletedTraining` manifests and failed closed before this sprint whenever a
  required product-row checkpoint pointer or live cluster publication was absent.

### Validation

```bash
docker compose run --rm jitml-cuda jitml test jitml-backends --linux-cuda
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

2026-07-06 status: upstream `linux-cpu` model-realness defects have been
replaced and validated, but CUDA row device evidence still requires a real
`linux-cuda` publisher/test run. The attempted live CUDA backend command failed
before row evidence could be minted because the host Docker daemon exposed no
NVIDIA GPU runtime to the `jitml-cuda` service.

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

## Sprint 29.3: CUDA Integration, E2E, and Attestation [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `29.2` real CUDA row evidence and a successful
`jitml-cuda` live integration/e2e run on a Docker-visible NVIDIA GPU.
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
  `DEVELOPMENT_PLAN/attestations/linux-cuda-report-card.md` records the 2026-07-05
  Phase `29` validation.

### Validation

```bash
docker compose run --rm jitml-cuda jitml test all --linux-cuda
docker compose run --rm jitml-cuda jitml test jitml-e2e --linux-cuda
docker compose run --rm jitml-cuda jitml test jitml-e2e --live --linux-cuda
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

2026-07-06 status: no current CUDA integration/e2e attestation is closed. The
source-side CUDA and negative-control work has landed, but this sprint remains
blocked until the real `linux-cuda` lane runs successfully and produces a fresh
attestation from device-backed row evidence.

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

## Documentation Requirements

**Engineering docs updated:**
- `documents/engineering/jit_codegen_architecture.md` — records the Phase `29`
  cuBLAS/cuDNN generated CUDA family surface and row-complete CUDA validation.
- `documents/engineering/numerical_core.md` — records the CUDA family kernels and
  CUDA device-backed product row evidence.
- `documents/engineering/unit_testing_policy.md` — records the Phase `29`
  `jitml-backends`, integration, e2e, and live Playwright coverage.
- `documents/engineering/purescript_frontend.md` — records CUDA-edge Playwright
  coverage of row-specific trained artifacts.

**Product docs to update:**
- `README.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`,
  and `DEVELOPMENT_PLAN/system-components.md` record the 2026-07-06 state:
  Phase `29` is Blocked on real `linux-cuda` validation because this host lacks a
  Docker-visible NVIDIA GPU runtime.

**Cross-references updated:**
- The refreshed `linux-cuda` attestation is linked from Phase `31` as a required
  input to final aggregation.

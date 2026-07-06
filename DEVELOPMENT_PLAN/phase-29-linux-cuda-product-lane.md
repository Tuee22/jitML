# Phase 29: linux-cuda Product Lane

**Status**: Active
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-28-per-model-integration-and-e2e.md](phase-28-per-model-integration-and-e2e.md), [phase-30-apple-silicon-product-lane.md](phase-30-apple-silicon-product-lane.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/jit_codegen_architecture.md](../documents/engineering/jit_codegen_architecture.md), [../documents/engineering/numerical_core.md](../documents/engineering/numerical_core.md)
**Generated sections**: none

> **Purpose**: Validate the row-complete product matrix on the real
> `linux-cuda` substrate, with generated CUDA family kernels invoking cuBLAS and
> cuDNN on the device path, without requiring Apple Silicon in the same phase.

## Phase State

🔄 **Active, reopened 2026-07-05 (realness audit).** Phase `29` previously
closed on 2026-07-05 on the real `linux-cuda` lane: the validation host exposed
an NVIDIA GeForce RTX 5090 through the NVIDIA Container Runtime (`nvidia-smi`:
driver `570.211.01`, CUDA `12.8`), `./bootstrap/linux-cuda.sh up` reconciled the
live CUDA cluster at edge `:9092`, all 12 canonical dataset artifacts were staged
into live MinIO through `jitml internal upload-dataset` with pinned SHA-256
verification, and all 55 ProductRows reported inference-eligible `latest`
checkpoint pointers.

**2026-07-05 reopen (realness audit).** That closure is **withdrawn**. The lane
did not measure anything real per row; it aggregated fabricated upstream
eligibility — the slack-0 tautological convergence gate (Phase `19`), the
hardcoded expert-controller RL reward (Phase `25`), and the residual-MLP "ResNet"
supervised stand-ins (Phase `24`) — so the `55 / 55` eligible and `71 / 71` live
Playwright product-matrix results are not real per-row evidence and are withdrawn
until Phases `19`–`28` re-close on real evidence. Separately, the CUDA kernels
this phase claims to exercise are still identity-copy stand-ins on the product
path in `src/JitML/Codegen/Cuda.hs`, and the typed cuBLAS/cuDNN probes in
`src/JitML/Engines/CublasBindings.hs` and `src/JitML/Engines/CudnnBindings.hs`
are dead on that path — already tracked in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md). All three
sprints reopen to Active; each names its unmet obligation and the
negative-control / per-model gate that closes it in `### Remaining Work`.

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

## Sprint 29.1: Real cuDNN/cuBLAS Kernels [🔄 Active]

**Status**: Active
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

2026-07-05 validation: `jitml-backends --linux-cuda` passed **21 / 21**,
including the Phase `29.1` generated-source cuBLAS/cuDNN assertion;
`jitml-unit --linux-cpu` passed **277 / 277**; `jitml check-code` passed.

Reopened on 2026-07-05 (realness audit): the generated CUDA family bodies in
`src/JitML/Codegen/Cuda.hs` are still identity-copy stand-ins on the product
path, and the typed cuBLAS/cuDNN probes in
`src/JitML/Engines/CublasBindings.hs` and `src/JitML/Engines/CudnnBindings.hs`
are dead — imported but never exercised by a product row. The backend assertions
therefore match `cublasSgemm` / `cudnnConvolutionForward` in rendered-source
text while no real GEMM/convolution runs on the attached GPU for a product row.
These residual identity-copy kernels and dead bindings are already tracked in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

### Remaining Work

- **Unmet Exit-Definition obligation (real device cuBLAS/cuDNN kernels).** The
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

## Sprint 29.2: CUDA Row Device Evidence [🔄 Active]

**Status**: Active
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

2026-07-05 validation: the CUDA runtime preflight, dataset staging, and
publisher runs completed with **55 / 55** product rows eligible and **0**
unsupported/error rows.

Reopened on 2026-07-05 (realness audit): the `55 / 55` eligible result was
aggregated from upstream fabricated per-row evidence — the slack-0 tautological
convergence gate (Phase `19`), the hardcoded expert-controller RL reward
(Phase `25`), and the residual-MLP "ResNet" supervised stand-ins (Phase `24`) —
so an inference-eligible `latest` pointer does not prove the CUDA-supported row
learned anything on the device. The eligibility claim is **withdrawn** until
those upstream phases re-close on real evidence.

### Remaining Work

- **Unmet Exit-Definition obligation (real per-row CUDA device evidence).** Every
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

## Sprint 29.3: CUDA Integration, E2E, and Attestation [🔄 Active]

**Status**: Active
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

2026-07-05 validation:

- `docker compose run --rm jitml-cuda jitml test all --linux-cuda` passed **8 / 8**
  stanzas. Notable sub-results: `jitml-unit` **277 / 277**,
  `jitml-integration` **137 / 137** with live WorkflowMatrix **837.24s** and live
  PPO convergence **263.51s**, `jitml-sl-canonicals` **31 / 31**,
  `jitml-rl-canonicals` **37 / 37**, `jitml-hyperparameter` **17 / 17**,
  `jitml-daemon-lifecycle` **32 / 32**, `jitml-e2e` **25 / 25**, and
  `jitml-backends` **21 / 21**.
- `docker compose run --rm jitml-cuda jitml test jitml-e2e --linux-cuda` passed
  **25 / 25**.
- `docker compose run --rm jitml-cuda jitml test jitml-e2e --live --linux-cuda`
  passed live Playwright **71 / 71** at edge `:9092` and reported
  `browser_product_matrix: checkpoint-backed product rows 55/55 served at edge :9092`.
- `docker compose run --rm jitml jitml docs check` passed.
- `docker compose run --rm jitml jitml check-code` passed.

Reopened on 2026-07-05 (realness audit): the row-complete integration/e2e claim
inherited the withdrawn Sprint `29.2` eligibility, so the live Playwright
`71 / 71` result and the `55 / 55` `e2e.product.*` row-specific pass are
**withdrawn** — a green browser render of a checkpoint whose eligibility was
fabricated upstream is not row-complete evidence. The refreshed CUDA report card
in `DEVELOPMENT_PLAN/attestations/linux-cuda-report-card.md` is withdrawn with
it.

### Remaining Work

- **Unmet Exit-Definition obligation (row-complete CUDA integration/e2e/
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
  and `DEVELOPMENT_PLAN/system-components.md` record the 2026-07-05 realness-audit
  reopen: Phase `29` is Active and its withdrawn `55 / 55` eligible / `71 / 71`
  live Playwright linux-cuda claim is not restored until Phases `19`–`28` re-close
  on real evidence.

**Cross-references updated:**
- The refreshed `linux-cuda` attestation is linked from Phase `31` as a required
  input to final aggregation.
